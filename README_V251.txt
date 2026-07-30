Iron Music 420 AI v2.5.1

FlutLab:
1. Import ZIP as a new project.
2. Run Pub get.
3. Build APK.
4. Install over the previous app to keep local data.

MacroDroid setup:
1. Create a macro.
2. Trigger: Intent Received.
3. Action string: com.ironmusic420ai.MACRODROID_COMMAND
4. Extra name: command, value pattern: *
5. Use the received extra to choose the actions in MacroDroid.
