const fs = require('fs');
const path = require('path');
const multer = require('multer');

// Upload directories
const UPLOAD_DIRS = {
    products: 'uploads/products',
    categories: 'uploads/categories',
    absensi: 'uploads/absensi',
    thumbnails: 'uploads/thumbnails',
    temp: 'uploads/temp'
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

// File filter for images only
const imageFileFilter = (req, file, cb) => {
    const allowedMimes = ['image/jpeg', 'image/jpg', 'image/png', 'image/gif', 'image/webp'];
    
    if (allowedMimes.includes(file.mimetype)) {
        cb(null, true);
    } else {
        cb(new Error('Invalid file type. Only JPEG, PNG, GIF, and WebP images are allowed.'), false);
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
    deleteFile
};
