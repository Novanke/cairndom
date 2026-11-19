///|
fn ssa_variable_names_json(
  program : FlowProgram,
  indices : Array[Int32],
) -> Json {
  let ordered = indices.copy()
  ordered.sort()
  Json::array(
    ordered.map(variable => Json::string(program.variables[variable])),
  )
}

///|
fn ssa_block_json(plan : SsaPlan, node : Int32, phi : Array[Int32]) -> Json {
  let program = plan.program
  Json::object(
    Map([
      ("id", Json::string(program.graph.nodes[node])),
      ("reachable", Json::boolean(plan.liveness.reachable[node])),
      ("defines", ssa_variable_names_json(program, program.definitions[node])),
      ("uses", ssa_variable_names_json(program, program.uses[node])),
      ("live_in", ssa_variable_names_json(program, plan.liveness.live_in[node])),
      (
        "live_out",
        ssa_variable_names_json(program, plan.liveness.live_out[node]),
      ),
      ("phi_variables", ssa_variable_names_json(program, phi)),
    ]),
  )
}

///|
fn ssa_placement_json(program : FlowProgram, placement : PhiPlacement) -> Json {
  let graph = program.graph
  Json::object(
    Map([
      ("variable", Json::string(program.variables[placement.variable])),
      ("definition_blocks", names_json(graph, placement.definitions)),
      ("live_in_blocks", names_json(graph, placement.live_in)),
      ("phi_blocks", names_json(graph, placement.phi_nodes)),
      ("requires_entry_value", Json::boolean(placement.requires_entry_value)),
    ]),
  )
}

///|
/// Compute a fresh plan and serialize cairndom.ssa-plan.v1 using original IDs.
/// The report contains phi locations and entry-value requirements, without IR
/// rewriting or variable renaming. Unreachable input facts remain visible but
/// contribute no liveness or placement results. Output is limited to 16 MiB.
pub fn ssa_plan_json_text(program : FlowProgram) -> String raise GraphError {
  prepare_ssa(program).json_text()
}

///|
// Serialize one block or placement at a time from a valid, privately owned plan.
fn bounded_ssa_plan_json_text(plan : SsaPlan) -> String raise GraphError {
  let program = plan.program
  let graph = program.graph
  let out : BoundedJsonWriter = {
    buffer: StringBuilder(),
    remaining: max_report_json_bytes,
    overflow_detail: "SSA plan JSON exceeds 16 MiB",
  }
  let phi_variables : Array[Array[Int32]] = Array::makei(graph.nodes.length(), _ => {
    []
  })
  let entry_values_required = []
  for placement in plan.placements {
    for node in placement.phi_nodes {
      phi_variables[node].push(placement.variable)
    }
    if placement.requires_entry_value {
      entry_values_required.push(
        Json::string(program.variables[placement.variable]),
      )
    }
  }
  let header = [
    ("schema", Json::string("cairndom.ssa-plan.v1")),
    ("entry", Json::string(graph.nodes[graph.entry])),
    ("scope", Json::string("entry_reachable_all_paths")),
    ("use_convention", Json::string("before_local_definition")),
    ("status", Json::string("locations_only")),
    ("variables", Json::array(program.variables.map(Json::string))),
  ]
  out.append("{\n")
  for (name, value) in header {
    out.field(name)
    out.value(value, "  ")
    out.append(",\n")
  }
  out.rows("blocks", graph.nodes.length(), node => {
    ssa_block_json(plan, node, phi_variables[node])
  })
  out.append(",\n")
  out.rows("placements", plan.placements.length(), index => {
    ssa_placement_json(program, plan.placements[index])
  })
  out.append(",\n")
  out.field("entry_values_required")
  out.value(Json::array(entry_values_required), "  ")
  out.append(",\n")
  out.field("entry_value_semantics")
  out.value(
    Json::string(
      "Variables live before entry local definitions require a caller-supplied parameter or initial value, or a missing-initialization diagnostic under the source language's rules.",
    ),
    "  ",
  )
  out.append("\n}")
  out.buffer.to_string()
}
