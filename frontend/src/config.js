/*
  config.js
  author: Kabera Clapton

  description: Build-time configuration from VITE_* environment variables. Fails loudly at startup
               if anything is missing, instead of failing later with a confusing network error.
*/
const required = {
  region: import.meta.env.VITE_REGION,
  apiUrl: import.meta.env.VITE_API_URL,
  userPoolId: import.meta.env.VITE_USER_POOL_ID,
  userPoolClientId: import.meta.env.VITE_USER_POOL_CLIENT_ID,
};

const missing = Object.entries(required).filter(([, value]) => !value).map(([key]) => key);
if (missing.length) {
  throw new Error(`Missing front-end configuration: ${missing.join(", ")}. See frontend/.env.example.`);
}

export const config = { ...required, apiUrl: required.apiUrl.replace(/\/$/, "") };
