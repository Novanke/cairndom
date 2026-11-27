///|
priv struct StageOwner {
  task : String
  output : String
  pid : Int32
  scope : String
  started : String
}

///|
extern "js" fn stage_current_pid() -> Int32 =
  #| () => process.pid

///|
extern "js" fn stage_random_task() -> String =
  #| () => process.getBuiltinModule('node:crypto').randomBytes(16).toString('hex')

///|
fn stage_owner_marker(binding : String, output : String) -> String {
  if binding.is_empty() {
    return ""
  }
  let pid = stage_current_pid()
  let probes = stage_processes([pid])
  let scope = probes.context()
  let started = probes.state(pid)
  if scope.is_empty() || started == "dead" || started.is_empty() {
    return ""
  }
  Json::object(
    Map([
      ("schema", Json::string("cairndom.stage-owner.v1")),
      ("binding", Json::string(binding)),
      ("task", Json::string(stage_random_task())),
      ("output", Json::string(output)),
      ("pid", Json::number(pid.to_double())),
      ("scope", Json::string(scope)),
      ("started", Json::string(started)),
    ]),
  ).stringify()
}

///|
fn stage_hex_id(value : StringView, length : Int32) -> Bool {
  value.length() == length &&
  value.iter().all(ch => (ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f'))
}

///|
fn stage_start_token(value : String) -> Bool {
  !value.is_empty() &&
  value.length() <= 20 &&
  value[:].iter().all(ch => ch >= '0' && ch <= '9')
}

///|
fn read_stage_owner(binding : String, marker : String) -> StageOwner? {
  if binding.is_empty() || marker.is_empty() {
    return None
  }
  // The file reader caps the marker at 4 KiB. Its schema requires flat fields.
  let value = @json.parse(marker, reject_duplicate_keys=true) catch {
    _ => return None
  }
  guard value is Object(fields) && fields.length() == 7 else { return None }
  guard fields.get("schema") == Some(Json::string("cairndom.stage-owner.v1")) &&
    fields.get("binding") == Some(Json::string(binding)) &&
    fields.get("task") is Some(String(task)) &&
    fields.get("output") is Some(String(output)) &&
    fields.get("pid") is Some(Number(number, ..)) &&
    fields.get("scope") is Some(String(scope)) &&
    fields.get("started") is Some(String(started)) else {
    return None
  }
  if number < 1.0 || number > 2147483647.0 {
    return None
  }
  let pid = number.to_int()
  let scope_hash = match scope.strip_prefix("linux:") {
    Some(hash) => Some(hash)
    None => scope.strip_prefix("win32:")
  }
  if pid.to_double() != number ||
    !stage_hex_id(task[:], 32) ||
    output.is_empty() ||
    output.contains("/") ||
    !(scope_hash is Some(hash) && stage_hex_id(hash, 64)) ||
    !stage_start_token(started) {
    return None
  }
  Some({ task, output, pid, scope, started, })
}

///|
fn stage_activity(
  owner : StageOwner,
  scope : String,
  sample : String,
) -> String {
  if scope != owner.scope {
    return "unknown"
  }
  if sample == owner.started {
    "active"
  } else if sample == "dead" || stage_start_token(sample) {
    "abandoned"
  } else {
    "unknown"
  }
}
