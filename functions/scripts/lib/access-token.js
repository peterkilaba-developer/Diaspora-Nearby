/** Obtains a short-lived Google access token from Application Default Credentials. */
const {google} = require("googleapis");

async function getAccessToken() {
  const auth = new google.auth.GoogleAuth({
    scopes: ["https://www.googleapis.com/auth/datastore"],
  });
  const client = await auth.getClient();
  const result = await client.getAccessToken();
  const token = typeof result === "string" ? result : result && result.token;
  if (!token) {
    throw new Error(
        "Application Default Credentials are unavailable. Run gcloud auth application-default login.",
    );
  }
  return token;
}

module.exports = {getAccessToken};
