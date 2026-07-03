// Firebase web app config for Tidbits Trivia online matching (Decision 040).
// These values are NOT secrets — Firebase web config is meant to ship in the
// client; access is controlled by Security Rules (database.rules.json) + the
// anonymous-auth requirement, not by hiding these. See
// docs/MATCHMAKING-SERVICES-RESEARCH.md for why Firebase RTDB.
export const FIREBASE_CONFIG = {
  apiKey: 'AIzaSyCns8iba6zVqkddEUY_gqoc4eVxz-3BGaA',
  authDomain: 'tidbits-trivia-f2ddb.firebaseapp.com',
  databaseURL: 'https://tidbits-trivia-f2ddb-default-rtdb.firebaseio.com',
  projectId: 'tidbits-trivia-f2ddb',
  storageBucket: 'tidbits-trivia-f2ddb.firebasestorage.app',
  messagingSenderId: '842242746909',
  appId: '1:842242746909:web:38fb7b101a35ddc26f74f4',
};
