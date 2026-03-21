# FlowMacHelper

This is a placeholder for the FlowMacHelper target.

The helper target can be used for:
- XPC service for privileged operations
- Background processing
- Launch agent for auto-start functionality

To add the helper target:
1. Create a new target in Xcode (File > New > Target)
2. Select "XPC Service" or "Command Line Tool"
3. Configure the target settings
4. Update the main app to communicate with the helper

## Use Cases

### XPC Service
If sandbox restrictions prevent certain operations in the main app,
an XPC service can perform privileged tasks on behalf of the app.

### Launch Agent
For auto-start at login functionality, a launch agent can be registered
with the system to start the app when the user logs in.
