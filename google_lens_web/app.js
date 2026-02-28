// Magic Lens App Logic

const fileInput = document.getElementById('fileInput');
const uploadTrigger = document.getElementById('uploadTrigger');
const dropZone = document.getElementById('dropZone');
const imageStage = document.getElementById('imageStage');
const sourceImage = document.getElementById('sourceImage');
const overlayContainer = document.getElementById('overlayContainer');
const loadingOverlay = document.getElementById('loadingOverlay');
const extractionGrid = document.getElementById('extractionGrid');
const infoPanel = document.getElementById('infoPanel');
const modeSwitch = document.getElementById('modeSwitch');
const newImageBtn = document.getElementById('newImageBtn');

let ocrResult = null;
let currentMode = 'lens'; // lens or highlight

// Initialize Listeners
uploadTrigger.addEventListener('click', () => fileInput.click());
newImageBtn.addEventListener('click', () => resetApp());

fileInput.addEventListener('change', (e) => {
    if (e.target.files.length > 0) {
        processImage(e.target.files[0]);
    }
});

// Drag and Drop
dropZone.addEventListener('dragover', (e) => {
    e.preventDefault();
    dropZone.classList.add('drag-over');
});

dropZone.addEventListener('dragleave', () => {
    dropZone.classList.remove('drag-over');
});

dropZone.addEventListener('drop', (e) => {
    e.preventDefault();
    dropZone.classList.remove('drag-over');
    if (e.dataTransfer.files.length > 0) {
        processImage(e.dataTransfer.files[0]);
    }
});

// Mode Switch
modeSwitch.addEventListener('change', (e) => {
    currentMode = e.target.checked ? 'highlight' : 'lens';
    updateOverlayMode();
});

async function processImage(file) {
    const reader = new FileReader();
    reader.onload = async (e) => {
        const url = e.target.result;
        sourceImage.src = url;

        // Show Stage
        dropZone.classList.add('hidden');
        imageStage.classList.remove('hidden');
        loadingOverlay.classList.remove('hidden');
        overlayContainer.innerHTML = '';
        infoPanel.classList.add('hidden');

        // Wait for image to load to get dimensions
        await new Promise(resolve => sourceImage.onload = resolve);

        runOCR(url);
    };
    reader.readAsDataURL(file);
}

async function runOCR(imageUrl) {
    try {
        const worker = await Tesseract.createWorker('eng');
        const { data } = await worker.recognize(imageUrl);
        await worker.terminate();

        ocrResult = data;
        createOverlays(data);
        extractAndShowData(data.text);

        loadingOverlay.classList.add('hidden');
        infoPanel.classList.remove('hidden');
    } catch (error) {
        console.error("OCR Error:", error);
        alert("Failed to analyze image. Please try again.");
        loadingOverlay.classList.add('hidden');
    }
}

function createOverlays(data) {
    overlayContainer.innerHTML = '';

    // Scale factors
    const imgWidth = sourceImage.naturalWidth;
    const imgHeight = sourceImage.naturalHeight;
    const displayWidth = sourceImage.clientWidth;
    const displayHeight = sourceImage.clientHeight;

    const scaleX = displayWidth / imgWidth;
    const scaleY = displayHeight / imgHeight;

    // We use blocks or words? Lines feel best for Google Lens rows
    data.lines.forEach(line => {
        const bbox = line.bbox;
        const overlay = document.createElement('div');
        overlay.className = 'text-overlay';

        // Positioning
        overlay.style.left = (bbox.x0 * scaleX) + 'px';
        overlay.style.top = (bbox.y0 * scaleY) + 'px';
        overlay.style.width = ((bbox.x1 - bbox.x0) * scaleX) + 'px';
        overlay.style.height = ((bbox.y1 - bbox.y0) * scaleY) + 'px';

        // Scaling Font size (approximate)
        const fontSize = (bbox.y1 - bbox.y0) * scaleY * 0.8;
        overlay.style.fontSize = fontSize + 'px';

        overlay.textContent = line.text.trim();
        overlayContainer.appendChild(overlay);
    });

    updateOverlayMode();
}

function updateOverlayMode() {
    if (currentMode === 'highlight') {
        overlayContainer.classList.add('highlight-mode');
    } else {
        overlayContainer.classList.remove('highlight-mode');
    }
}

function extractAndShowData(text) {
    extractionGrid.innerHTML = '';

    const patterns = {
        phones: {
            icon: '📞',
            title: 'Phone Numbers',
            regex: /(\+?\d{1,3}[-.\s]?)?(\(?\d{3}\)?[-.\s]?)?\d{3}[-.\s]?\d{4}/g
        },
        emails: {
            icon: '📧',
            title: 'Emails',
            regex: /[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/g
        },
        urls: {
            icon: '🔗',
            title: 'Links',
            regex: /\b(https?:\/\/|www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()@:%_\+.~#?&//=]*)/g
        },
        dates: {
            icon: '📅',
            title: 'Dates',
            regex: /\b\d{1,2}[\/-]\d{1,2}[\/-]\d{2,4}\b|\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]* \d{1,2}(?:st|nd|rd|th)?,? \d{4}\b/gi
        }
    };

    Object.entries(patterns).forEach(([key, config]) => {
        const matches = [...new Set(text.match(config.regex) || [])];
        if (matches.length > 0) {
            const card = document.createElement('div');
            card.className = 'data-card';

            card.innerHTML = `
                <div class="card-title">${config.icon} ${config.title}</div>
                <div class="card-items">
                    ${matches.map(m => `
                        <div class="data-item">
                            <span class="val">${m}</span>
                            <button class="copy-btn" onclick="copyText('${m.replace(/'/g, "\\'")}')">
                                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M8 17.7L2 12l6-5.7M22 12L16 17.7M16 6.3L22 12l-6 5.7M14 19l2-14"/></svg>
                            </button>
                        </div>
                    `).join('')}
                </div>
            `;
            extractionGrid.appendChild(card);
        }
    });
}

function copyText(text) {
    navigator.clipboard.writeText(text).then(() => {
        const btn = event.currentTarget;
        const originalHTML = btn.innerHTML;
        btn.innerHTML = '<span>Done!</span>';
        setTimeout(() => btn.innerHTML = originalHTML, 2000);
    });
}

function resetApp() {
    dropZone.classList.remove('hidden');
    imageStage.classList.add('hidden');
    infoPanel.classList.add('hidden');
    fileInput.value = '';
    overlayContainer.innerHTML = '';
}

// Window resize handling for overlays
window.addEventListener('resize', () => {
    if (ocrResult && !imageStage.classList.contains('hidden')) {
        createOverlays(ocrResult);
    }
});
