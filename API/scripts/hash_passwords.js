require('dotenv').config();
const bcrypt = require('bcrypt');
const pool = require('../src/db');

async function hashExistingPasswords() {
    try {
        console.log('Starting password hashing process...');
        
        // Get all users with plain text passwords
        const [users] = await pool.execute('SELECT id, username, password FROM users');
        
        console.log(`Found ${users.length} users to process`);
        
        for (const user of users) {
            // Check if password is already hashed (bcrypt hashes start with $2b$)
            if (user.password.startsWith('$2b$')) {
                console.log(`User ${user.username} already has hashed password, skipping...`);
                continue;
            }
            
            // Hash the plain text password
            const saltRounds = 12;
            const hashedPassword = await bcrypt.hash(user.password, saltRounds);
            
            // Update the user's password in the database
            await pool.execute(
                'UPDATE users SET password = ? WHERE id = ?',
                [hashedPassword, user.id]
            );
            
            console.log(`✓ Hashed password for user: ${user.username}`);
        }
        
        console.log('Password hashing completed successfully!');
        process.exit(0);
        
    } catch (error) {
        console.error('Error hashing passwords:', error);
        process.exit(1);
    }
}

// Run the script
hashExistingPasswords();