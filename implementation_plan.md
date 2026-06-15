Replace Antigravity with MiMo Code Agent
This plan outlines the replacement of the existing antigravity agent inside rdc with the MiMo Code agent (MiMo-Code-main). We will update the Python backend to run the MiMo agent via Bun, expose APIs for available models and functions, and update the Flutter mobile application to dynamically fetch and display these models and tools.

Proposed Changes
Backend — RDC Agent (Python)
[DELETE] 
antigravity_service.py
We will remove this file since it is the old LiteLLM-based Antigravity agent.

[NEW] 
mimo_service.py
A new service that interacts with the MiMo Code project:

Uses python subprocess.Popen to run the MiMo CLI via Bun: bun.exe run --cwd <mimo-path> --conditions=browser ./src/index.ts run --dir <project_path> --model <model_id> --format json "<prompt>"
Sets environmental variables: MIMOCODE_HOME pointing to MiMo-Code-main/.dev-home, and injecting the correct API key variable based on the selected model provider (e.g. GEMINI_API_KEY, OPENAI_API_KEY, ANTHROPIC_API_KEY, DEEPSEEK_API_KEY).
Reads the stdout of the process in real-time, parses each line as a JSON event, formats it as needed (e.g. parsing text, reasoning, tool_use events), and yields them for streaming.
[NEW] 
mimo.py
A new API router (replacing api/antigravity.py) which defines the endpoints:

POST /api/mimo/run: Executes the MiMo agent and streams output log in real-time (SSE).
GET /api/mimo/history/{project_id}: Retrieves past execution history (stored in database).
GET /api/mimo/run/{run_id}: Gets details of a specific execution.
GET /api/mimo/run/{run_id}/diff: Gets git diff of changed files.
POST /api/mimo/run/{run_id}/approve: Approves or reverts the session changes.
GET /api/mimo/models: Fetches the live list of models from https://models.dev/api.json, formats it with friendly names/icons/colors, caches it, and serves it to the client.
GET /api/mimo/functions: Returns a list of functions (tools) supported by MiMo Code (such as edit, write, read, grep, bash, etc.) with description and parameters.
[MODIFY] 
router.py
Remove api.antigravity import and routing, and add api.mimo routing under /api/mimo / /api/antigravity (we can keep backward-compatible paths or completely switch). We will route /api/mimo and keep /api/antigravity paths mapped to it for safety, or update the Flutter app fully.

[MODIFY] 
database.py
Update import of models.antigravity to the renamed or adapted model (e.g. keeping AntigravityRun model name or updating it to MimoRun in a clean way).

Frontend — Mobile App (Flutter)
[MODIFY] 
ai_model_picker.dart
Remove the hardcoded kAiModels list.
Fetch available models dynamically from /api/mimo/models on state initialization.
Show a loading indicator while fetching.
Map the JSON response to dynamic AiModelInfo objects (using logoAsset, color, keyUrl, keyHint provided by the API).
[MODIFY] 
antigravity_page.dart
Rename references from "Antigravity Agent" to "Mimo Agent".
Change the SSE endpoints to call /api/mimo/run and history endpoints to /api/mimo/history/....
Dynamically resolve model names from the fetched models list rather than kAiModels.
Add a panel/sheet or chip layout to list all the imported MiMo Code functions/tools, giving users visibility into what tools the agent has at its disposal (e.g. bash, edit, grep, write).
[MODIFY] 
workspace_page.dart
Rename the tab label from Antigravity to Mimo Agent (or Mimo).
Verification Plan
Automated Tests
Build and run the rdc/agent Python tests.
Compile/run the mimo agent command directly via bun to verify model execution and output streaming.
Manual Verification
Launch the RDC desktop agent and connect via the Flutter mobile application.
Select the Mimo tab in the workspace.
Open the AI configuration settings and verify that the models list is fetched dynamically from the backend.
Enter a prompt (e.g., "create a test file") and verify the execution streams real-time logs, correctly shows tool execution indicators (e.g. 🛠️ [Agente] Executando: write), and allows applying or reverting changes.
Verify the list of imported functions/tools is visible in the client UI.
