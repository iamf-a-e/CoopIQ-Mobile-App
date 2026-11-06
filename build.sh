#!/bin/bash
set -e
git clone https://github.com/flutter/flutter.git -b stable --depth 1 $HOME/flutter
export PATH="$PATH:$HOME/flutter/bin"
flutter config --enable-web
flutter pub get
flutter build web --release \
  --dart-define=GEMINI_API_KEY=$GEMINI_API_KEY \
  --dart-define=AGROVET_WHATSAPP=$AGROVET_WHATSAPP
