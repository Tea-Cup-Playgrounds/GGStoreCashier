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
];

// Allowed file extensions
const ALLOWED_IMAGE_EXTENSIONS = ['.jpg', '.jpeg', '.png'];

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
    // Check 1: MIME type — only jpeg/png
    if (!ALLOWED_IMAGE_MIMES.includes(file.mimetype)) {
        return cb(new Error('Tipe file tidak valid. Hanya gambar JPG dan PNG yang diizinkan.'), false);
    }

    // Check 2: Extension — only .jpg, .jpeg, .png
    const ext = path.extname(file.originalname).toLowerCase();
    if (!ALLOWED_IMAGE_EXTENSIONS.includes(ext)) {
        return cb(new Error('Ekstensi file tidak valid. Hanya .jpg, .jpeg, dan .png yang diizinkan.'), false);
    }

    // Check 3: Prevent path traversal
    const filename = path.basename(file.originalname);
    if (filename !== file.originalname || filename.includes('..')) {
        return cb(new Error('Nama file tidak valid.'), false);
    }

    cb(null, true);
};

// Post-upload validation (validates actual file content)
// filePath should be the absolute path as provided by multer's req.file.path
const validateUploadedImage = (filePath, mimeType) => {
    try {
        console.log('[validateUploadedImage] checking path:', filePath, '| mime:', mimeType);

        if (!fs.existsSync(filePath)) {
            throw new Error(`File tidak ditemukan: ${filePath}`);
        }

        // Validate file signature
        if (!validateFileSignature(filePath, mimeType)) {
            fs.unlinkSync(filePath);
            throw new Error('Konten file tidak sesuai format gambar. File ditolak karena alasan keamanan.');
        }

        // Additional size check
        const stats = fs.statSync(filePath);
        if (stats.size === 0) {
            fs.unlinkSync(filePath);
            throw new Error('File kosong terdeteksi.');
        }

        if (stats.size > 5 * 1024 * 1024) { // 5MB
            fs.unlinkSync(filePath);
            throw new Error('Ukuran file melebihi batas 5MB.');
        }

        console.log('[validateUploadedImage] passed, size:', stats.size);
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
