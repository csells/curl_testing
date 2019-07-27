// from https://nodejs.org/es/docs/guides/anatomy-of-an-http-transaction/
// run: node http-request-dump.js
const http = require('http');

var host = "localhost";
var port = 8080;
var server = http.createServer((req, res) => {
	const { method, url, headers } = req;
	let body = [];

	req.on('error', (err) => {
		console.log(`err: ${err}\n`);
	}).on('data', (chunk) => {
		body.push(chunk);
	}).on('end', () => {
		res.setHeader('Content-Type', 'application/json');
		res.end(JSON.stringify({ method, url, headers, body: body = Buffer.concat(body).toString() }) + "\n");
	});
}).listen(8080, () => {
	console.log(`listening on http://${host}:${port}`);
});
