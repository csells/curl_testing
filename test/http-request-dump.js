// from https://nodejs.org/es/docs/guides/anatomy-of-an-http-transaction/
// run: node http-request-dump.js
const http = require('http');

var host = "localhost";
var port = 28139;
var server = http.createServer((req, res) => {
	const { method, url, headers } = req;
	let body = [];

	req.on('error', (err) => {
		console.log(`err: ${err}\n`);
	}).on('data', (chunk) => {
		body.push(chunk);
	}).on('end', () => {
		res.setHeader('Content-Type', 'application/json');
		let out = JSON.stringify({ method, url, headers, body: body = decodeURIComponent(Buffer.concat(body).toString()) }) + "\n";
		console.log(out + "\n");
		res.end(out);
	});
}).listen(28139, () => {
	console.log(`listening on http://${host}:${port}`);
});
