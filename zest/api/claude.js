// One functions deployment, shared by all apps (ZEST-SPEC §8).
// The implementation lives with ZestMail, which is the only caller today;
// this root entry is where Vercel serves it for the whole origin (/api/claude),
// so the app works unchanged at /mail.
export { default } from '../apps/mail/api/claude.js';
