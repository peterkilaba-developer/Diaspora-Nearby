## Summary

- 

## Validation

- [ ] `flutter analyze`
- [ ] `flutter test`
- [ ] `npm test` in `firestore-rules-test` when rules change
- [ ] `npm test` in `blockchain` when contracts change
- [ ] `npm run lint` in `functions` when Cloud Functions change

## Branch Flow

- [ ] Feature and bugfix PR targets `dev`
- [ ] Release PR targets `staging`
- [ ] Production promotion targets `production`

## Security

- [ ] No secrets, Firebase service-account keys, signing files, or generated caches are committed
- [ ] Any new environment variables are documented in an `.env.example` file
