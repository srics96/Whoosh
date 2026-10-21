"""Point a local build at an already approved SDK; never install anything."""
import json, pathlib, sys, shutil
app,node,module=map(pathlib.Path,sys.argv[1:])
assert node.is_absolute() and node.is_file() and module.is_absolute() and module.is_file()
metadata=json.loads((module.parent/'package.json').read_text())
assert metadata['name']=='@anthropic-ai/claude-agent-sdk' and metadata['version']=='0.3.306'
# Packaging an existing approved dependency into the app is not a package install.
runtime=app/'Contents/Resources/ClaudeAdapter'
shutil.copytree(module.parent.parent.parent, runtime/'node_modules', dirs_exist_ok=True)
module=runtime/'node_modules/@anthropic-ai/claude-agent-sdk/sdk.mjs'
(runtime/'runtime.json').write_text(json.dumps({'node':str(node.resolve()),'sdkModule':'./node_modules/@anthropic-ai/claude-agent-sdk/sdk.mjs'}))
