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
extern "js" fn IoResult::stage_scan_complete(self : Self) -> Bool =
  #| result => result.complete

///|
extern "js" fn StageObservation::name(self : Self) -> String =
  #| entry => entry.name

///|
extern "js" fn StageObservation::observation(self : Self) -> String =
  #| entry => entry.observation

///|
extern "js" fn StageObservation::has_marker(self : Self) -> Bool =
  #| entry => !!entry.hasMarker

///|
extern "js" fn StageObservation::binding(self : Self) -> String =
  #| entry => entry.binding || ''

///|
extern "js" fn StageObservation::marker(self : Self) -> String =
  #| entry => entry.marker || ''

///|
extern "js" fn StageObservation::still_current(self : Self) -> Bool =
  #| entry => !!entry.confirm && entry.confirm()

///|
fn inspect_stages_command(args : Array[String]) -> Unit raise CommandError {
  let (directory, tasks) = match args {
    ["inspect-stages", "--tasks", "--", directory] if !directory.is_empty() =>
      (directory, true)
    ["inspect-stages", "--tasks", directory] if !directory.is_empty() &&
      !directory.has_prefix("-") => (directory, true)
    ["inspect-stages", "--", directory] if !directory.is_empty() =>
      (directory, false)
    ["inspect-stages", directory] if !directory.is_empty() &&
      !directory.has_prefix("-") => (directory, false)
    _ => raise CommandError("usage", "expected inspect-stages [--] DIRECTORY")
  }
  let result = file_io(
    if tasks {
      "inspect-stage-tasks"
    } else {
      "inspect-stages"
    },
    directory,
    "",
    _ => (),
    stage_owner_marker,
  )
  if result.error() != "" {
    raise CommandError("io", result.error())
  }
  let observations = result.stage_rows()[:].to_owned()
  observations.sort_by((left, right) => left.name().compare(right.name()))
  let owners = observations.map(entry => {
    read_stage_owner(entry.binding(), entry.marker())
  })
  let pids = []
  if tasks {
    for value in owners {
      if value is Some(owner) {
        pids.push(owner.pid)
      }
    }
  }
  let probes = stage_processes(FixedArray::from_array(pids[:]))
  let entries = observations.mapi((index, entry) => {
    let owner = owners[index]
    let physical = entry.observation()
    let current = tasks &&
      owner is Some(_) &&
      physical != "changed" &&
      entry.still_current()
    let observation = if tasks && owner is Some(_) && !current {
      "changed"
    } else if entry.has_marker() &&
      owner is None &&
      (
        physical == "empty" ||
        physical == "data_only" ||
        physical == "data_with_other_links"
      ) {
      "unexpected_contents"
    } else {
      physical
    }
    let possible_residue = match observation {
      "empty" | "data_only" | "data_with_other_links" => true
      _ => false
    }
    let fields = Map([
      ("name", Json::string(entry.name())),
      ("observation", Json::string(observation)),
      ("possible_residue", Json::boolean(possible_residue)),
    ])
    if tasks {
      if current && owner is Some(record) {
        fields["ownership"] = Json::string("recorded")
        fields["activity"] = Json::string(
          stage_activity(record, probes.context(), probes.state(record.pid)),
        )
        fields["task_id"] = Json::string(record.task)
        fields["output"] = Json::string(record.output)
      } else {
        fields["ownership"] = Json::string("unverified")
        fields["activity"] = Json::string("unknown")
        fields["task_id"] = Json::null()
        fields["output"] = Json::null()
      }
    }
    Json::object(fields)
  })
  let report_fields = Map([
    (
      "schema",
      Json::string(
        if tasks {
          "cairndom.stage-inspection.v2"
        } else {
          "cairndom.stage-inspection.v1"
        },
      ),
    ),
    ("directory", Json::string(result.stage_directory())),
  ])
  if !tasks {
    report_fields["ownership"] = Json::string("unverified")
    report_fields["activity"] = Json::string("unknown")
  } else if !result.stage_scan_complete() {
    report_fields["scan_complete"] = Json::boolean(false)
  }
  report_fields["entries"] = Json::array(entries)
  let report = Json::object(report_fields).stringify(indent=2) + "\n"
  if utf8_byte_length(report) > 16777216 {
    raise CommandError("limit", "output exceeds 16 MiB")
  }
  ignore(io("stdout", "", text=report))
}
