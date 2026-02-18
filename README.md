# The Joy Programming Language

A language made for fun and to learn more about compilers

> [!NOTE]
> This is only tested to compile and run with Odin dev-2026-02


### Syntax
```
use joy.debug;

decl main = fn() {
	debug.println("Hello, World!");
};
```

### Progress

- [x] Lexing
- [x] Parsing (multithreaded)
- [x] Typechecking (multithreaded)
- [x] Custom IR (multithreaded)
- [ ] Custom backend (Sea of Nodes) (in-progress)
- [ ] Metaprogramming (maybe. this might be out of the scope of the language)
