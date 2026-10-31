# CoopIQ (Flutter)

Poultry and livestock health app for urbanmunda.com. Structure follows DawaMom:
Home, Ask (grounded chat), Diagnose (computer vision), Flock, Agrovet.

## First run

```bash
unzip coopiq_flutter.zip && cd coopiq
flutter create --org africa.coopiq --project-name coopiq .   # adds android/ and ios/, keeps lib/
flutter pub get
flutter run --dart-define=GEMINI_API_KEY=YOUR_KEY --dart-define=AGROVET_WHATSAPP=260XXXXXXXXX
```

## Platform setup after `flutter create`

iOS, `ios/Runner/Info.plist`:
```xml
<key>NSCameraUsageDescription</key><string>Take photos of droppings, birds and livestock for diagnosis.</string>
<key>NSPhotoLibraryUsageDescription</key><string>Choose photos for diagnosis.</string>
<key>LSApplicationQueriesSchemes</key><array><string>https</string><string>mailto</string></array>
```

Android, `android/app/src/main/AndroidManifest.xml`, inside `<manifest>`:
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<queries>
  <intent><action android:name="android.intent.action.VIEW"/><data android:scheme="https"/></intent>
  <intent><action android:name="android.intent.action.SENDTO"/><data android:scheme="mailto"/></intent>
</queries>
```

## Where things live

- `assets/data/poultry_rag.jsonl`: the grounding file (105 passages). Retrieval is on-device (`services/rag_service.dart`), so the library and the offline chat fallback work without signal.
- `services/gemini_service.dart`: grounded chat and the image diagnosis call. Retrieved passages are passed in as context for both.
- `screens/diagnose_screen.dart`: the CV tab (camera or upload, subject picker, notes, result card, escalate to agrovet, history).
- `core/models.dart`: broiler vaccination schedule, taken from the grounding file.
- `core/theme.dart`: all colors. Replace with the exact hex values from the website CSS.

## Before shipping

1. The Diagnose tab uses a general vision model, not a trained classifier. To match how CaCx works in DawaMom, train or fine-tune on labelled droppings and livestock images, then implement the same `diagnose()` signature against that model (on-device TFLite or your API). Nothing in the UI changes.
3. Have an agrovet review the prompt in `diagnose()` and the disease list.
4. Nyanja, Bemba, Lozi and Tonga replies come from the model's own ability in those languages. Have native speakers check them.
