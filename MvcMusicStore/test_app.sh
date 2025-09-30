#!/bin/bash

# Parse command line arguments
WAIT_FOR_KEYPRESS=false
if [[ "$1" == "--wait" || "$1" == "-w" ]]; then
    WAIT_FOR_KEYPRESS=true
fi

# Set environment variable for connection string override
export ConnectionStrings__MusicStoreEntities="Data Source=database-2.ce0zbn2eruko.us-east-1.rds.amazonaws.com,1433;Initial Catalog=MvcMusicEntities;User ID=admin;Password=KCCZD5Vs0m2j1HhWKqMh;TrustServerCertificate=True"

echo "Starting application with environment variable override..."
echo "Connection string: $ConnectionStrings__MusicStoreEntities"

export ASPNETCORE_ENVIRONMENT=Development

# Build the application with output to /tmp
echo "Building application..."
export DOTNET_CLI_TELEMETRY_OPTOUT=1
export NUGET_PACKAGES=/tmp/nuget
rm -rf /tmp/obj /tmp/bin
mkdir -p /tmp/obj /tmp/bin
dotnet build --output /tmp/build --configuration Debug -p:BaseIntermediateOutputPath=/tmp/obj/ -p:BaseOutputPath=/tmp/bin/

# Start the application from tmp build directory
echo "Starting application from /tmp/build..."
cd /tmp/build
dotnet MvcMusicStore.dll --urls="http://0.0.0.0:80" > /tmp/app.log 2>&1 &
APP_PID=$!

echo "Application started with PID: $APP_PID"
echo "Waiting for application to start..."
sleep 5

# Test the application
echo "Testing application..."
curl -s -o /tmp/response.html http://0.0.0.0:80/ 
CURL_EXIT=$?

if [ $CURL_EXIT -eq 0 ]; then
    echo "✅ Application responded successfully!"
    echo "Response saved to /tmp/response.html"
else
    echo "❌ Application failed to respond"
fi

sleep 2

# Check logs for any database errors
echo "Checking logs for errors..."
if grep -i "fail" /tmp/app.log; then
    echo "❌ Found error in logs"
    cat /tmp/app.log
else
    echo "✅ No errors found"
fi

# Wait for keypress if flag is set
if [ "$WAIT_FOR_KEYPRESS" = true ]; then
    echo "Press any key to stop the application..."
    read -n 1 -s
fi

# Kill the application
echo "Stopping application..."
kill $APP_PID
wait $APP_PID 2>/dev/null

echo "Test completed!"
