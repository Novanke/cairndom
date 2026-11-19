///|
#external
priv type StageObservation

///|
extern "js" fn IoResult::stage_directory(self : Self) -> String =
  #| result => result.directory

///|
extern "js" fn IoResult::stage_rows(
  self : Self,
) -> FixedArray[StageObservation] =
  #| result => result.rows

///|
extern "js" fn StageObservation::name(self : Self) -> String =
  #| entry => entry.name

///|
extern "js" fn StageObservation::observation(self : Self) -> String =
  #| entry => entry.observation

///|
fn inspect_stages_command(args : Array[String]) -> Unit raise CommandError {
  let directory = match args {
    ["inspect-stages", "--", directory] if !directory.is_empty() => directory
    ["inspect-stages", directory] if !directory.is_empty() &&
      !directory.has_prefix("-") => directory
    _ => raise CommandError("usage", "expected inspect-stages [--] DIRECTORY")
  }
  let result = file_io("inspect-stages", directory, "", detail => {
    print_error("io", detail)
  })
  if result.error() != "" {
    raise CommandError("io", result.error())
  }
  let observations = result.stage_rows()[:].to_owned()
  observations.sort_by((left, right) => left.name().compare(right.name()))
  let entries = observations.map(entry => {
    let observation = entry.observation()
    let possible_residue = match observation {
      "empty" | "data_only" | "data_with_other_links" => true
      _ => false
    }
    Json::object(
      Map([
        ("name", Json::string(entry.name())),
        ("observation", Json::string(observation)),
        ("possible_residue", Json::boolean(possible_residue)),
      ]),
    )
  })
  let report = Json::object(
      Map([
        ("schema", Json::string("cairndom.stage-inspection.v1")),
        ("directory", Json::string(result.stage_directory())),
        ("ownership", Json::string("unverified")),
        ("activity", Json::string("unknown")),
        ("entries", Json::array(entries)),
      ]),
    ).stringify(indent=2) +
    "\n"
  if utf8_byte_length(report) > 16777216 {
    raise CommandError("limit", "output exceeds 16 MiB")
  }
  ignore(io("stdout", "", text=report))
}
