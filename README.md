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

