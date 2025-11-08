// App.js
import React from "react";
import { useAuth } from "react-oidc-context";

function App() {
  const auth = useAuth();

  // ✅ Sign-out handler (Cognito Hosted UI)
  const signOutRedirect = () => {
    const clientId = "cilent-id";
    const logoutUri = "http://localhost:3000"; // must match Cognito logout URL exactly
    const cognitoDomain =
      "your-domain";

    // Use the full Cognito logout endpoint
    window.location.href = `${cognitoDomain}/logout?client_id=${clientId}&logout_uri=${encodeURIComponent(
      logoutUri
    )}&response_type=code`;
  };

  if (auth.isLoading) return <div>Loading...</div>;
  if (auth.error) return <div>Error: {auth.error.message}</div>;

  if (auth.isAuthenticated) {
    return (
      <div style={{ padding: "2rem", textAlign: "center" }}>
        <h2>Welcome 👋</h2>
        <p><b>Email:</b> {auth.user?.profile?.email}</p>

        <details style={{ textAlign: "left", margin: "1rem auto", width: "80%" }}>
          <summary>Token Info</summary>
          <pre>ID Token: {auth.user?.id_token}</pre>
          <pre>Access Token: {auth.user?.access_token}</pre>
          <pre>Refresh Token: {auth.user?.refresh_token}</pre>
        </details>

        {/* ✅ Sign out button */}
        <button onClick={signOutRedirect}>Sign Out</button>
      </div>
    );
  }

  return (
    <div style={{ textAlign: "center", marginTop: "50px" }}>
      <h2>React + AWS Cognito Login</h2>
      <button onClick={() => auth.signinRedirect()}>Sign In</button>
    </div>
  );
}

export default App;
