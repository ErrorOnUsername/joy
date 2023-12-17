# The Joy Programming Language

A language made for fun and to learn more about compilers


### Syntax
(this is speculative and `#import` isn't implemented yet)

```
decl IO := #import "core:io"

decl main : ()
{
    IO.println( "Hello, World!" );
}
```

### Progress

- [x] Lexing
- [x] Parsing (multithreaded)
- [ ] Typechecking (in-progress. multithreaded)
- [ ] Custom IR
- [ ] Custom backend (maybe also llvm just to learn? not sure)


I will say a lot of the code is pretty jank since this is not only the first serious thing I've done in Odin, but also the first real compiler I'm trying to make aside from a previous failed attempt in Rust and a really bad Lisp interpreter that never really worked.
