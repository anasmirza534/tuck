import envoy
import filepath
import gleam/bit_array
import gleam/crypto
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import gleam/time/calendar
import gleam/time/timestamp
import simplifile

pub type Metadata {
  Metadata(
    hash: String,
    orig_path: String,
    stored_as: String,
    file_size: Int,
    added_at: String,
  )
}

pub fn print_metadata(metadata: Metadata) -> Nil {
  io.println("")
  io.println("Metadata:")
  io.println("  hash      = " <> metadata.hash)
  io.println("  orig_path = " <> metadata.orig_path)
  io.println("  stored_as = " <> metadata.stored_as)
  io.println("  file_size = " <> metadata.file_size |> int.to_string())
  io.println("  added_at  = " <> metadata.added_at)
  io.println("")
}

pub fn make_hash(bit_array: BitArray) -> String {
  crypto.Sha256
  |> crypto.hash(bit_array)
  |> bit_array.base16_encode()
  |> string.lowercase()
}

pub fn get_ts() -> timestamp.Timestamp {
  timestamp.system_time()
}

pub fn ts_to_utc_string(ts: timestamp.Timestamp) -> String {
  timestamp.to_rfc3339(ts, calendar.utc_offset)
}

pub fn get_db_file_path() -> Result(String, String) {
  use home <- result.try(
    "HOME"
    |> envoy.get()
    |> result.replace_error("Error getting `HOME` env variable."),
  )

  let db_dir_path = filepath.join(home, ".local/share/tuck")

  use _ <- result.try(
    db_dir_path
    |> simplifile.create_directory_all()
    |> result.map_error(fn(error) {
      "Error creating database directory, path: "
      <> db_dir_path
      <> ", error: "
      <> simplifile.describe_error(error)
    }),
  )

  Ok(filepath.join(db_dir_path, "tuck.db"))
}

pub fn get_day_str(ts: timestamp.Timestamp) -> String {
  let #(calendar.Date(year, month, day), _tod) =
    timestamp.to_calendar(ts, calendar.local_offset())

  let month = calendar.month_to_int(month)
  let date_str =
    [year, month, day]
    |> list.map(fn(d) {
      d
      |> int.to_string()
      |> string.pad_start(to: 2, with: "0")
    })
    |> string.join("-")

  date_str
}
