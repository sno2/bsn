<img src="./playground/public/logo.jpg" width="150" alt="bsn">

An implementation of @face-hh 's
[Bussin esoteric language](https://github.com/face-hh/bussin) written in Zig.

## Playground

The playground is available at https://trybsn.vercel.app. It is the easiest way
to play around with this interpreter.

## Known Issues

- The playground terminal looks weird after running multiple times.
- The playground is not interactive. We currently run programs and display the
  output from `println` calls at the end of the program. Although, after the
  [self-hosted Zig compiler implements async again](https://github.com/ziglang/zig/issues/6025),
  I will use it to add streaming IO.
- Printing circular objects causes stack overflows.
- All other TODOs in the code.
