# summary
A very barebones informal/personal helper CLI tool
for streamlining cmake project creation, building and running.
Written in zig as a personal challenge and goal while learning the language.
# todo
* high priority
    * allow for overriding config arguments in the cli commands
    * present feedback when processing a command
    * relative config file
    * `globals.json` for user speific information like toolchain file specifications etc.
* medium priority
    * streamline command convention
    * store templates as a compressed file
    - [x] allow templates to have subdirectories
* low
    * add safeguard for overriding a config.json when it failed to parse
    * help command for argument options
# ideas
utilize zig's type reflection for merging an incomplete local project config into the global settings
