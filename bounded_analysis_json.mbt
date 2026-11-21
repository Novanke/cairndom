///|
let max_report_json_bytes : Int32 = 16_777_216

///|
priv struct BoundedJsonWriter {
  buffer : StringBuilder
  mut remaining : Int32
  overflow_detail : String
}

///|
// This writer receives only the fixed report vocabulary and JSON made from
// validated ASCII node and variable IDs. UTF-16 code units equal UTF-8 bytes.
fn BoundedJsonWriter::append(
  self : Self,
  fragment : StringView,
) -> Unit raise GraphError {
  if fragment.length() > self.remaining {
    raise Invalid(self.overflow_detail)
  }
  self.remaining -= fragment.length()
  self.buffer.write_view(fragment)
}

///|
// Render one record with the standard JSON formatter, then add the leading
// indentation for its position in the report. Only this record is held here.
fn BoundedJsonWriter::value(
  self : Self,
  value : Json,
  continuation_indent : StringView,
) -> Unit raise GraphError {
  let serialized = value.stringify(indent=2)
  let mut first = true
  for line in serialized[:].split("\n") {
    if !first {
      self.append("\n")
      self.append(continuation_indent)
    }
    self.append(line)
    first = false
  }
}

///|
fn BoundedJsonWriter::field(
  self : Self,
  name : String,
) -> Unit raise GraphError {
  let key = Json::string(name).stringify()
  self.append("  ")
  self.append(key[:])
  self.append(": ")
}

///|
fn BoundedJsonWriter::rows(
  self : Self,
  name : String,
  count : Int32,
  row : (Int32) -> Json,
) -> Unit raise GraphError {
  self.field(name)
  self.append("[")
  for index in 0..<count {
    if index > 0 {
      self.append(",")
    }
    self.append("\n    ")
    self.value(row(index), "    ")
  }
  if count > 0 {
    self.append("\n  ")
  }
  self.append("]")
}

///|
// Reuse the quoted IDs across witnesses. Every row has the same three fields
// and indentation as the legacy formatter, without a Map and line iterator.
fn BoundedJsonWriter::witness_rows(
  self : Self,
  graph : Graph,
  witnesses : Array[ControlWitness],
) -> Unit raise GraphError {
  self.field("control_witnesses")
  self.append("[")
  if !witnesses.is_empty() {
    let names = graph.nodes.map(name => Json::string(name).stringify())
    for index, witness in witnesses {
      if index > 0 {
        self.append(",")
      }
      let controller = names[witness.controller]
      let successor = names[witness.successor]
      let dependent = names[witness.dependent]
      let row = "\n    {\n      \"controller\": \{controller},\n      \"successor\": \{successor},\n      \"dependent\": \{dependent}\n    }"
      self.append(row[:])
    }
    self.append("\n  ")
  }
  self.append("]")
}

///|
fn bounded_analysis_json_text(
  result : Analysis,
  limit : Int32,
  include_witnesses~ : Bool,
) -> String raise GraphError {
  let (schema, overflow_detail) = if include_witnesses {
    ("cairndom.analysis.v1", "analysis JSON exceeds the byte limit")
  } else {
    (
      "cairndom.analysis-summary.v1", "analysis summary JSON exceeds the byte limit",
    )
  }
  let out : BoundedJsonWriter = {
    buffer: StringBuilder(),
    remaining: limit,
    overflow_detail,
  }
  out.append("{\n")
  for index, (name, value) in analysis_report_fields(result, schema) {
    if index > 0 {
      out.append(",\n")
    }
    out.field(name)
    out.value(value, "  ")
  }
  for (name, count, row) in analysis_report_sections(result) {
    out.append(",\n")
    out.rows(name, count, row)
  }
  if include_witnesses {
    // The sorted prefix determines the completeness flag before the rows.
    let (witnesses, complete) = bounded_control_witnesses_of(result)
    out.append(",\n")
    out.field("control_witnesses_complete")
    out.append(if complete { "true" } else { "false" })
    out.append(",\n")
    out.field("control_witness_limit")
    let witness_limit = max_control_witnesses.to_string()
    out.append(witness_limit[:])
    out.append(",\n")
    out.witness_rows(result.graph, witnesses)
  }
  out.append("\n}")
  out.buffer.to_string()
}
