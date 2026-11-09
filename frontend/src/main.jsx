/*
  main.jsx
  author: Kabera Clapton

  description: Entry point. Configures Amplify with the Cognito user pool and renders the app behind
               Amplify UI's Authenticator (sign-up hidden: only admins create accounts).
*/
import "@fontsource/barlow/400.css";
import "@fontsource/barlow/500.css";
import "@fontsource/barlow/600.css";
import "@fontsource/barlow-condensed/600.css";
import "@fontsource/barlow-condensed/700.css";
import "@aws-amplify/ui-react/styles.css";
import "./styles.css";

import { Authenticator } from "@aws-amplify/ui-react";
import { Amplify } from "aws-amplify";
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import App from "./App";
import { config } from "./config";

Amplify.configure({
  Auth: {
    Cognito: {
      userPoolId: config.userPoolId,
      userPoolClientId: config.userPoolClientId,
      loginWith: { email: true },
    },
  },
});

function SignInHeader() {
  return (
    <div className="signin-header">
      <img src="/favicon.svg" alt="" width="40" height="40" />
      <h1>Field Tasks</h1>
      <p>Sign in with the email your admin registered.</p>
    </div>
  );
}

createRoot(document.getElementById("root")).render(
  <StrictMode>
    <Authenticator hideSignUp components={{ Header: SignInHeader }}>
      {({ signOut }) => <App signOut={signOut} />}
    </Authenticator>
  </StrictMode>,
);
