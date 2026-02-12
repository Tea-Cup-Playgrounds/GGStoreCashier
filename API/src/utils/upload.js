const fs = require('fs');
const path = require('path');
const multer = require('multer');

// Upload directories (relative to project root where server is run)
const UPLOAD_DIRS = {
    products: 'API/uploads/products',
    categories: 'API/uploads/categories',
    absensi: 'API/uploads/absensi',
    thumbnails: 'API/uploads/thumbnails',
    temp: 'API/uploads/temp'
};

// Allowed image MIME types
const ALLOWED_IMAGE_MIMES = [
    'image/jpeg',
    'image/jpg', 
    'image/png', 
    'image/gif', 
    'image/webp'
];

// Allowed file extensions
const ALLOWED_IMAGE_EXTENSIONS = ['.jpg', '.jpeg', '.png', '.gif', '.webp'];

// Magic numbers (file signatures) for image validation
const IMAGE_SIGNATURES = {
    'image/jpeg': [
        [0xFF, 0xD8, 0xFF, 0xE0], // JPEG JFIF
        [0xFF, 0xD8, 0xFF, 0xE1], // JPEG Exif
        [0xFF, 0xD8, 0xFF, 0xE2], // JPEG
        [0xFF, 0xD8, 0xFF, 0xE3], // JPEG
        [0xFF, 0xD8, 0xFF, 0xDB], // JPEG
    ],
    'image/png': [[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]],
    'image/gif': [
        [0x47, 0x49, 0x46, 0x38, 0x37, 0x61], // GIF87a
        [0x47, 0x49, 0x46, 0x38, 0x39, 0x61], // GIF89a
    ],
    'image/webp': [[0x52, 0x49, 0x46, 0x46]], // RIFF (WebP container)
};

// Validate file signature (magic numbers)
const validateFileSignature = (filePath, mimeType) => {
    try {
        const buffer = Buffer.alloc(12); // Read first 12 bytes
        const fd = fs.openSync(filePath, 'r');
        fs.readSync(fd, buffer, 0, 12, 0);
        fs.closeSync(fd);

        const signatures = IMAGE_SIGNATURES[mimeType];
        if (!signatures) return false;

        // Check if file starts with any of the valid signatures
        return signatures.some(signature => {
            return signature.every((byte, index) => buffer[index] === byte);
        });
    } catch (error) {
        console.error('Error validating file signature:', error);
        return false;
    }
};

// Ensure upload directories exist
const ensureUploadDirs = () => {
    Object.values(UPLOAD_DIRS).forEach(dir => {
        const fullPath = path.join(process.cwd(), dir);
        if (!fs.existsSync(fullPath)) {
            fs.mkdirSync(fullPath, { recursive: true });
            console.log(`Created upload directory: ${dir}`);
        }
    });
};

// Configure multer storage for products
const productStorage = multer.diskStorage({
    destination: (req, file, cb) => {
        cb(null, UPLOAD_DIRS.products);
    },
    filename: (req, file, cb) => {
        const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
        const ext = path.extname(file.originalname);
        cb(null, `product-${uniqueSuffix}${ext}`);
    }
});

// Configure multer storage for categories
const categoryStorage = multer.diskStorage({
    destination: (req, file, cb) => {
        cb(null, UPLOAD_DIRS.categories);
    },
    filename: (req, file, cb) => {
        const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
        const ext = path.extname(file.originalname);
        cb(null, `category-${uniqueSuffix}${ext}`);
    }
});

// Configure multer storage for absensi
const absensiStorage = multer.diskStorage({
    destination: (req, file, cb) => {
        cb(null, UPLOAD_DIRS.absensi);
    },
    filename: (req, file, cb) => {
        const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
        const ext = path.extname(file.originalname);
        cb(null, `absensi-${uniqueSuffix}${ext}`);
    }
});

// Enhanced file filter for images only with multiple security checks
const imageFileFilter = (req, file, cb) => {
    // Check 1: MIME type validation
    if (!ALLOWED_IMAGE_MIMES.includes(file.mimetype)) {
        return cb(new Error('Invalid file type. Only JPEG, PNG, GIF, and WebP images are allowed.'), false);
    }

    // Check 2: File extension validation
    const ext = path.extname(file.originalname).toLowerCase();
    if (!ALLOWED_IMAGE_EXTENSIONS.includes(ext)) {
        return cb(new Error('Invalid file extension. Only .jpg, .jpeg, .png, .gif, and .webp are allowed.'), false);
    }

    // Check 3: Filename validation (prevent path traversal)
    const filename = path.basename(file.originalname);
    if (filename !== file.originalname || filename.includes('..')) {
        return cb(new Error('Invalid filename detected.'), false);
    }

    // Check 4: Prevent executable extensions disguised as images
    const dangerousExtensions = ['.exe', '.sh', '.bat', '.cmd', '.com', '.pif', '.scr', '.vbs', '.js', '.jar', '.php', '.asp', '.aspx'];
    const fullFilename = file.originalname.toLowerCase();
    if (dangerousExtensions.some(ext => fullFilename.includes(ext))) {
        return cb(new Error('Suspicious file detected.'), false);
    }

    cb(null, true);
};

// Post-upload validation (validates actual file content)
const validateUploadedImage = (filePath, mimeType) => {
    try {
        // Validate file signature
        if (!validateFileSignature(filePath, mimeType)) {
            fs.unlinkSync(filePath); // Delete invalid file
            throw new Error('File content does not match image format. File has been rejected for security reasons.');
        }

        // Additional size check
        const stats = fs.statSync(filePath);
        if (stats.size === 0) {
            fs.unlinkSync(filePath);
            throw new Error('Empty file detected.');
        }

        if (stats.size > 5 * 1024 * 1024) { // 5MB
            fs.unlinkSync(filePath);
            throw new Error('File size exceeds 5MB limit.');
        }

        return true;
    } catch (error) {
        throw error;
    }
};

// Multer upload configurations
const uploadProduct = multer({
    storage: productStorage,
    fileFilter: imageFileFilter,
    limits: {
        fileSize: 5 * 1024 * 1024 // 5MB limit
    }
});

const uploadCategory = multer({
    storage: categoryStorage,
    fileFilter: imageFileFilter,
    limits: {
        fileSize: 5 * 1024 * 1024 // 5MB limit
    }
});

const uploadAbsensi = multer({
    storage: absensiStorage,
    fileFilter: imageFileFilter,
    limits: {
        fileSize: 5 * 1024 * 1024 // 5MB limit
    }
});

// Delete file helper
const deleteFile = (filePath) => {
    try {
        const fullPath = path.join(process.cwd(), filePath);
        if (fs.existsSync(fullPath)) {
            fs.unlinkSync(fullPath);
            console.log(`Deleted file: ${filePath}`);
            return true;
        }
        return false;
    } catch (error) {
        console.error(`Error deleting file ${filePath}:`, error);
        return false;
    }
};

module.exports = {
    UPLOAD_DIRS,
    ensureUploadDirs,
    uploadProduct,
    uploadCategory,
    uploadAbsensi,
    deleteFile,
    validateUploadedImage, // Export for post-upload validation
    ALLOWED_IMAGE_MIMES,
    ALLOWED_IMAGE_EXTENSIONS
};
