const crypto = require("node:crypto");
const fs = require("fs");

const { privateKey, publicKey } = crypto.generateKeyPairSync("rsa", {
  modulusLength: 2048,
});

const { kty, n, e } = publicKey.export({ format: "jwk" });

const kid = crypto
  .createHash("sha256")
  .update(publicKey.export({ format: "der", type: "spki" }))
  .digest("base64url");

const jwk = {
  kty,
  alg: "RS256",
  use: "sig",
  e,
  n,
  kid,
};

const jwks = {
  keys: [jwk],
};

fs.writeFileSync(
  "sa-signer.key",
  privateKey.export({ format: "pem", type: "pkcs1" })
);
fs.writeFileSync(
  "sa-signer-pkcs8.pub",
  publicKey.export({ format: "pem", type: "spki" })
);
fs.writeFileSync("jwks.json", JSON.stringify(jwks, null, 2));
