const path = require('path');
const { TwitterApi } = require('../functions/node_modules/twitter-api-v2');
require('../functions/node_modules/dotenv').config({ path: path.resolve(__dirname, '../functions/.env') });

const client = new TwitterApi({
  appKey: process.env.X_API_KEY,
  appSecret: process.env.X_API_KEY_SECRET,
  accessToken: process.env.X_ACCESS_TOKEN,
  accessSecret: process.env.X_ACCESS_TOKEN_SECRET,
});

async function test() {
  try {
    const user = await client.v2.me();
    console.log('✅ SUCCESS! Authenticated as:', user.data.name, '(@' + user.data.username + ')');
    console.log('User ID:', user.data.id);
  } catch (error) {
    console.error('❌ FAILED!', error?.data || error.message);
  }
}

test();
