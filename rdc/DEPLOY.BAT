echo
del "c:/adb/app-debug.apk"
copy  C:\Users\hp909\Downloads\RemoteCode-main\RemoteCode-main\rdc\mobile\build\app\outputs\flutter-apk\app-debug.apk c:/adb
cd c:/adb
adb install app-debug.apk

pause