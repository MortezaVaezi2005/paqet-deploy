@echo off
setlocal
echo Paqet Client Setup for Windows
echo SERVER_IP: {{SERVER_IP}}
echo PORT: {{PAQET_PORT}}
echo VERSION: {{PAQET_VERSION}}

if exist paqet.exe (
    if exist client.yaml (
        echo Paqet already installed and configured. Starting...
        paqet.exe run -c client.yaml
        pause
        exit /b
    ) else (
        echo Paqet binary found but configuration missing. Skipping download...
        goto :config_setup
    )
)

echo Downloading yq...
powershell -Command "Invoke-WebRequest -Uri 'https://github.com/mikefarah/yq/releases/latest/download/yq_windows_amd64.exe' -OutFile 'yq.exe'"

echo Downloading Paqet...
set VERSION={{PAQET_VERSION}}
powershell -Command "Invoke-WebRequest -Uri 'https://github.com/hanselime/paqet/releases/download/%VERSION%/paqet-windows-amd64-%VERSION%.zip' -OutFile 'paqet.zip'"

echo Extracting...
powershell -Command "Expand-Archive -Path 'paqet.zip' -DestinationPath '.'"

:config_setup
echo Preparing Configuration...
if exist paqet_windows_amd64 (
    cd paqet_windows_amd64
    copy /Y ..\yq.exe .
)

echo role: client > client.yaml
yq -i ".log.level = \"info\"" client.yaml
yq -i ".transport.protocol = \"kcp\"" client.yaml
yq -i ".transport.kcp.mode = \"fast\"" client.yaml

set /p LOCAL_PORT="Enter Local Listen Port (default: 1080): "
if "%LOCAL_PORT%"=="" set LOCAL_PORT=1080

set /p AUTH_ENABLE="Enable SOCKS5 Authentication? (y/N): "
set AUTH_USER=""
set AUTH_PASS=""
if /I "%AUTH_ENABLE%"=="y" (
    set /p AUTH_USER="Username: "
    set /p AUTH_PASS="Password: "
)

echo Applying Configuration...
yq -i ".network.ipv4.addr = \"{{SERVER_IP}}:{{PAQET_PORT}}\"" client.yaml
yq -i ".transport.kcp.key = \"{{SECRET_KEY}}\"" client.yaml
yq -i ".listen.addr = \":%LOCAL_PORT%\"" client.yaml

if /I "%AUTH_ENABLE%"=="y" (
    yq -i ".socks.user = \"%AUTH_USER%\"" client.yaml
    yq -i ".socks.pass = \"%AUTH_PASS%\"" client.yaml
) else (
    yq -i "del(.socks.user)" client.yaml
    yq -i "del(.socks.pass)" client.yaml
)

echo Starting Paqet...
paqet.exe run -c client.yaml
pause
