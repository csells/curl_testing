// from https://nodejs.org/es/docs/guides/anatomy-of-an-http-transaction/
// run: node http-request-dump.js [-json]
const http = require('http');

// check for json output
var jsonFormat = process.argv.length != 2 && process.argv[2] == '--json';
var host = "localhost";
var port = 8080;
var server = http.createServer((req, res) => {
	const { headers, method, url } = req;
	let body = [];

	req.on('error', (err) => {
		console.log(`err: ${err}\n`);
	}).on('data', (chunk) => {
		body.push(chunk);
	}).on('end', () => {
		if (jsonFormat) {
			res.setHeader('Content-Type', 'application/json');
			res.end(JSON.stringify({ headers, method, url, body }) + "\n");
		} else {
			res.setHeader('Content-Type', 'plain/text');
			res.write(`url: ${url}\n`);
			res.write(`method: ${method}\n`);
			res.write(`headers:\n`);
			Object.keys(headers).sort().forEach(k => res.write(`  ${k}: '${headers[k]}'\n`));
			res.write(`body:\n`);
			Object.values(body).forEach(v => res.write(`  ${v}\n`));
			res.end();
		}
	});
}).listen(8080, () => {
	console.log(`listening in ${jsonFormat ? "JSON format" : "normal format"} mode on http://${host}:${port}`);
});
