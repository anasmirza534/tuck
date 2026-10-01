# tuck

CLI based application for renaming files and storing thier metadata.

[![Package Version](https://img.shields.io/hexpm/v/tuck)](https://hex.pm/packages/tuck)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://tuck.hexdocs.pm/)

```sh
gleam add tuck@1
```
```gleam
import tuck

pub fn main() -> Nil {
  // TODO: An example of the project in use
}
```

Further documentation can be found at <https://tuck.hexdocs.pm/>.

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
```

## Test

create test file

```sh
dd if=/dev/urandom of=test-20mb.bin bs=1m count=20
```

and run 

```sh
gleam run
```
