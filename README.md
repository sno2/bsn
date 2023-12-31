<img src="./playground/public/logo.png" width="150" alt="bsn">

An implementation of @face-hh 's
[Bussin esoteric language](https://github.com/face-hh/bussin) written in Zig
with a custom bytecode virtual machine and component-based mark and sweep
garbage collector.

## Playground

The playground is available at https://trybsn.vercel.app. It is the easiest way
to play around with this interpreter.

## Known Issues

- The playground does not maintain extra newlines when transforming between the
  BS and BSX formats.
- The playground is not interactive. We currently run programs and display the
  output from `println` calls at the end of the program. Although, after the
  [self-hosted Zig compiler implements async again](https://github.com/ziglang/zig/issues/6025),
  I will use it to add streaming IO.
- Printing circular objects causes stack overflows.
  ```
  lit a be {} rn
  a.a be a

  "Stack overflow"
  waffle(a)
  ```
- Parsing errors can have incorrect formatting in some cases.
- Functions do not support capturing locals, but globals do work.
  ```
  bruh foo() {
      lit a be 24

      bruh bar() {
          a
      }

      bar
  }

  "This will fail because it does not know about 'a'"
  foo()()
  ```
- All other TODOs in the code.

## License

[MIT](./LICENSE)
