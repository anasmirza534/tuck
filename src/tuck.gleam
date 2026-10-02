import argv
import database.{
  init_database, insert_metadata, select_by_name, select_file_by_hash,
  select_file_by_stored_as, select_file_by_trunced_hash, select_files,
}
import filepath
import gleam/bool
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import glugify
import input.{input}
import internal.{
  Metadata, get_day_str, get_ts, make_hash, print_metadata, ts_to_utc_string,
}
import simplifile
import sqlight

pub fn main() -> Nil {
  let res = sqlight.with_connection("tuck.db", run)

  case res {
    Ok(_) -> Nil
    Error(msg) -> {
      io.println_error(msg)
      halt(1)
    }
  }
}

fn run(conn: sqlight.Connection) -> Result(Nil, String) {
  use _ <- result.try(conn |> init_database())

  case argv.load().arguments {
    [] -> no_args_command()
    ["add", path] -> path |> add_command(conn)
    ["show", hash] -> hash |> show_command(conn)
    ["ls"] -> conn |> list_command()
    ["find", text] -> text |> find_command(conn)
    ["info", path] -> path |> info_command(conn)
    ["help"] -> help_command()
    unknown_args -> unknown_command(unknown_args)
  }
}

fn no_args_command() -> Result(Nil, String) {
  get_usage_info()
  |> list.prepend("")
  |> list.prepend("No subcommand provided. Check usage with `help`")
  |> string.join("\n")
  |> Error()
}

fn help_command() -> Result(Nil, String) {
  get_usage_info()
  |> string.join("\n")
  |> io.println()

  Ok(Nil)
}

fn unknown_command(args: List(String)) -> Result(Nil, String) {
  get_usage_info()
  |> list.prepend("")
  |> list.prepend(
    "Unknown command: "
    <> args |> string.join(" ")
    <> ". Check usage with `help`",
  )
  |> string.join("\n")
  |> Error()
}

fn add_command(
  file_path: String,
  conn: sqlight.Connection,
) -> Result(Nil, String) {
  use path <- result.try(
    file_path
    |> absname()
    |> filepath.expand()
    |> result.replace_error("Invalid path: " <> file_path),
  )

  use exists <- result.try(
    path
    |> simplifile.is_file()
    |> result.replace_error("File permission issue, path: " <> path),
  )

  use <- bool.guard(
    when: exists |> bool.negate(),
    return: Error("Its not a file, path: " <> path),
  )

  use file_info <- result.try(
    path
    |> simplifile.file_info()
    |> result.replace_error("Could not get file info, path: " <> path),
  )

  use file_bits <- result.try(
    path
    |> simplifile.read_bits()
    |> result.replace_error("Could not read file, path" <> path),
  )

  let hash = file_bits |> make_hash()
  let hash_sliced = hash |> string.slice(0, 16)

  let name = path |> filepath.base_name()
  let name_without_ext =
    name
    |> filepath.strip_extension()
    |> glugify.slugify()
    |> string.slice(0, 16)
    |> string.remove_suffix("-")

  let ts = get_ts()
  let added_at = ts |> ts_to_utc_string()
  let date_str = get_day_str(ts)

  let stored_as =
    date_str
    <> "_"
    <> hash_sliced
    <> "_"
    <> name_without_ext
    <> {
      case filepath.extension(name) {
        Ok(ext) -> "." <> ext
        Error(_) -> ""
      }
    }

  let file_path_to = path |> filepath.directory_name |> filepath.join(stored_as)

  use db_files <- result.try(
    hash
    |> select_file_by_hash(conn)
    |> result.map_error(fn(error) {
      "Error finding file in db, path: " <> path <> " , error: " <> error
    }),
  )

  let existing_orig_path =
    db_files
    |> list.map(fn(db_file) { db_file.orig_path })
    |> string.join("")

  use <- bool.guard(
    when: {
      db_files
      |> list.is_empty()
      |> bool.negate()
    },
    return: Error(
      "File already exists in db, path: "
      <> path
      <> " | original paths: "
      <> existing_orig_path,
    ),
  )

  let metadata = Metadata(hash, path, stored_as, file_info.size, added_at)
  metadata |> print_metadata()

  let user_answer =
    input("Do you want to add and rename to " <> file_path_to <> ": [y/N]: ")
    |> result.unwrap("n")
    |> string.lowercase()

  use <- bool.guard(
    when: user_answer != "y",
    return: Error("User rejected prompt"),
  )

  use _ <- result.try(
    metadata
    |> insert_metadata(conn)
    |> result.map_error(fn(error) {
      "Error inserting record in db, path: " <> path <> " , error: " <> error
    }),
  )

  use _ <- result.try(
    simplifile.rename(at: path, to: file_path_to)
    |> result.map_error(fn(error) {
      "Error renaming file: " <> simplifile.describe_error(error)
    }),
  )

  io.println("File added with hash: " <> metadata.hash)

  Ok(Nil)
}

fn show_command(hash: String, conn: sqlight.Connection) -> Result(Nil, String) {
  let hash_len = hash |> string.length()

  use <- bool.guard(
    when: hash_len < 4,
    return: "Hash should be atleast 4 characters, hash: "
      |> string.append(hash)
      |> Error(),
  )

  use db_files <- result.try(
    case hash_len < 64 {
      True -> hash |> select_file_by_trunced_hash(conn)
      False -> hash |> select_file_by_hash(conn)
    }
    |> result.map_error(fn(error) {
      "Error finding file in db, hash: " <> hash <> " , error: " <> error
    }),
  )

  case db_files {
    [] ->
      "No file found for given hash: "
      |> string.append(hash)
      |> Error()
    [db_file_metadata] -> {
      db_file_metadata |> print_metadata()
      Ok(Nil)
    }
    many_files -> {
      many_files
      |> list.each(fn(db_file_metadata) {
        db_file_metadata
        |> print_metadata()
      })

      "Multiple files found for given hash: "
      |> string.append(hash)
      |> Error()
    }
  }
}

fn list_command(conn: sqlight.Connection) -> Result(Nil, String) {
  use db_files <- result.try(
    select_files(conn)
    |> result.map_error(fn(error) { "Error querying db, error: " <> error }),
  )

  case db_files {
    [] -> io.println("No files found in db.")
    db_files -> {
      db_files
      |> list.each(fn(db_file) {
        db_file
        |> print_metadata()
      })

      io.println(
        "Total files: "
        <> {
          db_files
          |> list.length()
          |> int.to_string()
        },
      )
    }
  }

  Ok(Nil)
}

fn info_command(
  file_path: String,
  conn: sqlight.Connection,
) -> Result(Nil, String) {
  use path <- result.try(
    file_path
    |> absname()
    |> filepath.expand()
    |> result.replace_error("Invalid path: " <> file_path),
  )

  use exists <- result.try(
    path
    |> simplifile.is_file()
    |> result.replace_error("File permission issue, path: " <> path),
  )

  use <- bool.guard(
    when: exists |> bool.negate(),
    return: Error("Its not a file, path: " <> path),
  )

  let name = path |> filepath.base_name()

  use db_files <- result.try(
    name
    |> select_file_by_stored_as(conn)
    |> result.map_error(fn(error) {
      "Error finding file in db, path: " <> path <> " , error: " <> error
    }),
  )

  case db_files {
    [] -> Error("File not tracked by tuck, path: " <> path)
    [db_file_metadata] -> {
      db_file_metadata |> print_metadata()
      Ok(Nil)
    }
    many_files -> {
      many_files
      |> list.each(fn(db_file_metadata) {
        db_file_metadata
        |> print_metadata()
      })

      Error("Multiple db entries found for file, path: " <> path)
    }
  }
}

fn find_command(text: String, conn: sqlight.Connection) -> Result(Nil, String) {
  use <- bool.guard(
    when: text |> string.length() < 3,
    return: "Text should be more than 3 characters, text: "
      |> string.append(text)
      |> Error(),
  )

  use db_files <- result.try(
    text
    |> select_by_name(conn)
    |> result.map_error(fn(error) { "Error querying db, error: " <> error }),
  )

  case db_files {
    [] -> io.println("No files found in db.")
    db_files -> {
      db_files
      |> list.each(fn(db_file) {
        db_file
        |> print_metadata()
      })

      io.println(
        "Total files: "
        <> {
          db_files
          |> list.length()
          |> int.to_string()
        },
      )
    }
  }

  Ok(Nil)
}

fn get_usage_info() -> List(String) {
  [
    "tuck: Command line utility to manage file metadata",
    "",
    "usage: tuck <sub-command>",
    "  ls                     list all files tracked by tuck",
    "  add <file-path>        hash, store metadata and rename a file",
    "  show <hash>            show metadata for a file by hash (or prefix)",
    "  info <file-path>       show metadata for an already-stored file",
    "  find <text>            search stored files by original or stored name",
    "  help                   show this usage info",
  ]
}

@external(erlang, "filename", "absname")
fn absname(path: String) -> String

@external(erlang, "erlang", "halt")
fn halt(code: Int) -> Nil
