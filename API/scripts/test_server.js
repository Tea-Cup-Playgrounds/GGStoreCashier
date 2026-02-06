require('dotenv').config();
const http = require('http');

async function testServer() {
    const port = process.env.PORT || 5000;
    const hosts = ['localhost', '127.0.0.1'];
    
    console.log('Testing server connectivity...');
    console.log(`Expected port: ${port}`);
    
    for (const host of hosts) {
        try {
            console.log(`\nTesting ${host}:${port}...`);
            
            const options = {
                hostname: host,
                port: port,
                path: '/api/test',
                method: 'GET',
                headers: {
                    'Content-Type': 'application/json'
                }
            };
            
            const response = await new Promise((resolve, reject) => {
                const req = http.request(options, (res) => {
                    let data = '';
                    res.on('data', (chunk) => {
                        data += chunk;
                    });
                    res.on('end', () => {
                        resolve({
                            statusCode: res.statusCode,
                            data: data
                        });
                    });
                });
                
                req.on('error', (err) => {
                    reject(err);
                });
                
                req.setTimeout(5000, () => {
                    req.destroy();
                    reject(new Error('Request timeout'));
                });
                
                req.end();
            });
            
            console.log(`✓ ${host}:${port} - Status: ${response.statusCode}`);
            console.log(`  Response: ${response.data}`);
            
        } catch (error) {
            console.log(`✗ ${host}:${port} - Error: ${error.message}`);
        }
    }
    
    console.log('\nServer test completed.');
}

testServer();