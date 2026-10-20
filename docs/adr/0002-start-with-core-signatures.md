# Start with core signatures

The first release shifts the signatures in upstream RBS's `core/` directory. Signatures in `stdlib/` are outside the first release because library versions can vary independently of the Ruby version. Starting with core gives us a target that can be defined by the Ruby version before adding library version selection.
