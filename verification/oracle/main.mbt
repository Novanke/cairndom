///|
#external
priv type Input

///|
extern "js" fn arguments() -> FixedArray[String] =
  #| () => process.argv.slice(2)

///|
extern "js" fn read_input() -> Input =
  #| () => {
  #|   try {
  #|     const fs = process.getBuiltinModule('node:fs');
  #|     const chunks = [], buffer = new Uint8Array(65536);
  #|     let total = 0, count;
  #|     while ((count = fs.readSync(0, buffer, 0, buffer.length)) > 0) {
  #|       total += count;
  #|       if (total > 2097152) throw Error('reference input exceeds 2 MiB');
  #|       chunks.push(buffer.slice(0, count));
  #|     }
  #|     const bytes = new Uint8Array(total);
  #|     let offset = 0;
  #|     for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  #|     return {text: new TextDecoder('utf-8', {fatal:true}).decode(bytes), error:''};
  #|   } catch (error) { return {text:'', error:String(error.message || error)}; }
  #| }

///|
extern "js" fn Input::text(self : Self) -> String =
  #| value => value.text

///|
extern "js" fn Input::error(self : Self) -> String =
  #| value => value.error

///|
extern "js" fn emit(text : String, failed : Bool) -> Unit =
  #| (text, failed) => {
  #|   if (failed) process.exitCode = 2;
  #|   const output = failed ? process.stderr : process.stdout;
  #|   output.once('error', () => { process.exitCode = 2; });
  #|   output.write(text + '\n');
  #| }

///|
fn source() -> Json raise {
  let input = read_input()
  if input.error() != "" {
    fail(input.error())
  }
  @json.parse(input.text(), max_nesting_depth=16, reject_duplicate_keys=true)
}

///|
fn stage_report_expected(input : Json) -> Json raise {
  let (directory, pending, empty, linked) = match input {
    [String(directory), String(pending), String(empty), String(linked)] =>
      (directory, pending, empty, linked)
    _ => fail("expected directory and three staging fixture names")
  }
  let fixtures = [
    (pending, "data_only"),
    (empty, "empty"),
    (linked, "data_with_other_links"),
  ]
  fixtures.sort_by((a, b) => a.0.compare(b.0))
  let entries : Array[Json] = fixtures.map(fixture => {
    let (name, observation) = fixture
    { "name": name, "observation": observation, "possible_residue": true }
  })
  {
    "schema": "cairndom.stage-inspection.v1",
    "directory": directory,
    "ownership": "unverified",
    "activity": "unknown",
    "entries": entries,
  }
}

///|
fn run() -> Json raise {
  let args = arguments()
  if args.length() != 1 {
    fail("expected one reference command")
  }
  match args[0] {
    "graph" => @reference.graph_expected(source())
    "program" => @reference.program_expected(source())
    "graph-cases" => @reference.graph_cases()
    "program-cases" => @reference.program_cases()
    "invalid-cases" => @reference.invalid_cases()
    "host-cases" => @reference.host_cases()
    "stage-report" => stage_report_expected(source())
    "query" => @reference.query_expected(source())
    "query-cases" => @reference.query_cases()
    "query-invalid-cases" => @reference.query_invalid_cases()
    "value-origins" => @reference.value_origins_expected(source())
    "value-origins-cases" => @reference.value_origins_cases()
    "value-origin-limit-cases" => @reference.value_origin_limit_cases()
    _ => fail("unknown reference command")
  }
}

///|
fn main {
  emit(run().stringify(), false) catch {
    error => emit(Json::string(error.to_string()).stringify(), true)
  }
}
