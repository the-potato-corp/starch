Yeah — seeing the parser changes my recommendation quite a bit.

 You have a **concrete syntax-ish AST immediately after parsing**, with source positions, and you're already consistently representing _expressions_ as `Node`s. In that context, I would make source-level names nodes much more consistently.

 ## The biggest inconsistency

 You currently have three different representations for essentially the same thing:

```
# expression
identifier -> NodeKind.identifier

# declaration
varName -> Node

# other declarations
paramName -> string
funcName -> string
className -> string
derivedName -> string

# some references
watchTarget -> string
```

 I'd strongly recommend standardizing this.

 ### I'd change these

```
parameter:
    paramName*: Node

derivedVariable:
    derivedName*: Node

watchStatement:
    watchTarget*: Node

functionDeclaration:
    funcName*: Node

classDeclaration:
    className*: Node
    classParent*: Node
```

 So, for example:

```
let name = self.expect(TokenType.ident)

return node(token, self.peek(-1), NodeKind.functionDeclaration,
    funcName = node(name, name, NodeKind.identifier,
        name = name.value.strVal),
    ...
)
```

 Though I'd probably make a helper:

```
proc parse_identifier(self: Parser): Node =
    let token = self.expect(TokenType.ident)
    return node(token, token, NodeKind.identifier,
        name = token.value.strVal)
```

 Then:

```
let name = self.parse_identifier()
```

 and everything becomes much cleaner.

---

 # But there's an important distinction

 I **wouldn't** turn every `string` into a `Node`.

 For example:

```
tryCatches*: seq[tuple[kind: Node, variable: string, body: seq[Node]]]
```

 The `kind` is clearly a type/name expression, so `Node` makes sense.

 But `variable` is the name introduced by:

```
catch Exception as e {}
```

 I'd make that a `Node` too **if it is source syntax you're going to care about**.

 So:

```
tryCatches*: seq[tuple[kind: Node, variable: Node, body: seq[Node]]]
```

 with `nil` representing an omitted binding.

 Similarly, your imports could use nodes.

---

 # Your `watch` is particularly telling

 You have:

```
let identifier = self.expect(TokenType.ident).value.strVal
```

 That tells me `watch` currently only permits a bare identifier:

```
watch foo {}
```

 If that's intentional, `watchTarget: Node` is still preferable because it is a source-level name.

 But if you eventually want:

```
watch foo.bar {}
```

 you've already got the machinery to represent that:

```
memberAccess
├── identifier("foo")
└── identifier("bar")
```

 So using a `Node` now doesn't lock you into the current grammar.

---

 # `classParent` should absolutely be a Node

 This one I'd change without hesitation.

 Currently:

```
var parent: string = ""

if self.current.kind == TokenType.is:
    discard self.advance()
    parent = self.expect(TokenType.ident).value.strVal
```

 I'd do:

```
var parent: Node = nil

if self.current.kind == TokenType.is:
    discard self.advance()
    parent = self.parse_identifier()
```

 Then:

```
class Foo is Bar {}
```

 becomes conceptually:

```
classDeclaration
├── className: identifier("Foo")
└── classParent: identifier("Bar")
```

 That's much more coherent with your existing type AST.

 And if you later allow:

```
class Foo is SomeNamespace.Bar {}
```

 or generics, you've already got the right abstraction.

---

 # `derivedDependencies` is different

 This:

```
derivedDependencies*: HashSet[string]
```

 is actually the one I **wouldn't** replace with `HashSet[Node]`.

 The parser is doing semantic-ish work here:

```
let dependencies = self.find_identifiers(value)
```

 That's not really syntax anymore.

 For:

```
derive x = foo + bar.baz;
```

 you're extracting:

```
{"foo", "baz"}
```

 That's a dependency set.

 I'd actually consider moving this **out of the parser AST entirely**.

 Something like:

```
source
  ↓
lexer
  ↓
parser
  ↓
AST
  ↓
name/dependency analysis
  ↓
semantic information
```

 The AST should ideally just contain:

```
derivedValue*: Node
```

 and a later analysis pass can calculate:

```
derivedDependencies: HashSet[string]
```

 or, even better eventually, resolved symbol IDs.

 There's also a subtle bug/semantic question in your current implementation:

```
of NodeKind.memberAccess:
    result = self.findIdentifiers(node.accessMember)
```

 For:

```
foo.bar
```

 you return `bar`, not `foo`.

 That might be exactly what you want if `bar` is the dependency, but it's unusual if dependencies mean "variables referenced by this expression." If `foo` is the actual variable and `bar` is a property, you'd normally expect `foo`.

 So this part deserves some thought.

---

 # Your type representation is good

 This:

```
genericType:
    genericKind*: Node
    typeArgs*: seq[Node]

typeOptional:
    optionalKind*: Node

typeUnion:
    unionKinds*: seq[Node]
```

 is actually a strong argument for using nodes for names everywhere.

 For:

```
Map[string, int]?
```

 you're already producing a structural representation:

```
typeOptional
└── genericType
    ├── identifier("Map")
    ├── identifier("string")
    └── identifier("int")
```

 So having:

```
funcReturnKind: Node
```

 but:

```
funcName: string
```

 is the odd part.

---

 # One thing I would _not_ change

 I wouldn't create separate `IdentifierNode` types just to distinguish declarations from references.

 Your current:

```
NodeKind.identifier:
    name*: string
```

 is perfectly reasonable for the parse AST.

 Later, semantic analysis can determine whether:

```
foo
```

 is:

 - a variable reference
- a function reference
- a type
- a module
- a class
- etc.

 The parser shouldn't need to know that.

---

 # I'd make your AST roughly this

 The relevant changes:

```
of NodeKind.parameter:
    paramName*: Node
    paramHint*: Node
    paramDefault*: Node

of NodeKind.derivedVariable:
    derivedName*: Node
    derivedHint*: Node
    derivedValue*: Node
    # dependencies probably removed from parse AST

of NodeKind.watchStatement:
    watchTarget*: Node
    watchBody*: seq[Node]

of NodeKind.functionDeclaration:
    funcName*: Node
    funcParams*: seq[Node]
    funcReturnKind*: Node
    funcBody*: seq[Node]

of NodeKind.classDeclaration:
    className*: Node
    classParent*: Node
    classFields*: seq[Node]
    classMethods*: seq[Node]
    classWatchers*: seq[Node]
    classDerivatives*: seq[Node]
```

 And potentially:

```
of NodeKind.tryStatement:
    tryCatches*: seq[tuple[
        kind: Node,
        variable: Node,
        body: seq[Node]
    ]]
```

 For imports, I'd probably revisit the representation separately because your `using` syntax is unusual enough that there's a more interesting AST design question there.

 ## One other thing I noticed

 You have:

```
of NodeKind.unaryOp:
    unaryOperator*: TokenType
    unaryOperand*: Node
```

 and then:

```
if token.kind in {TokenType.minus, TokenType.bang, TokenType.await, TokenType.yield}:
```

 but your `NodeKind` also has:

```
await, yield
```

 So currently `await foo` and `yield foo` are represented as:

```
unaryOp(await, foo)
```

 rather than:

```
await(foo)
yield(foo)
```

 That may be intentional, but the presence of dedicated `NodeKind.await` and `NodeKind.yield` suggests the AST design and parser have drifted slightly.

 **That's actually the kind of thing where seeing the full parser was very useful.** There are a few places where I can now see opportunities to make the AST substantially more coherent, rather than just changing `string` → `Node` mechanically.
