use godot::prelude::*;

mod print;

struct GiloExtension;

#[gdextension]
unsafe impl ExtensionLibrary for GiloExtension {}

#[derive(GodotClass)]
#[class(base = Node)]
struct PrintNode {
    base: Base<Node>,
}

#[godot_api]
impl INode for PrintNode {
    fn init(base: Base<Node>) -> Self {
        Self { base }
    }

    fn ready(&mut self) {
        print::hello_world();
    }
}