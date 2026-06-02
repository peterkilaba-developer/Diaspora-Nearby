@echo off
set JAVA_HOME=C:\Program Files\Microsoft\jdk-17.0.18.8-hotspot
set ANDROID_HOME=C:\Users\Nemo CLAW\AppData\Local\Android\Sdk
set PATH=%JAVA_HOME%\bin;C:\flutter\bin;C:\Program Files\nodejs;C:\Users\Nemo CLAW\AppData\Roaming\npm;C:\Program Files\Git\cmd;%PATH%

cd /d "C:\Projects\DiasporaNearby"

echo Skipping clean...

echo Building APK...
call flutter.bat build apk

if exist "build\app\outputs\flutter-apk\app-release.apk" (
    echo Installing APK on connected device...
    call flutter.bat install
    
    echo Copying APK to landing area...
    copy /Y "build\app\outputs\flutter-apk\app-release.apk" "landing\downloads\diaspora-nearby.apk"
    
    echo Deploying Firebase Hosting...
    call firebase.cmd deploy --only hosting:landing
    
    echo Process completed!
) else (
    echo Flutter build failed to produce an APK.
    exit /b 1
)
