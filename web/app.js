// InclusiChat Web — Micro-interactions & Demo Logic

document.addEventListener('DOMContentLoaded', () => {
  // 1. Calculadora Interactiva en la sección de Camuflaje
  const display = document.getElementById('calc-demo-display');
  const keys = document.querySelectorAll('.calc-key');
  let currentVal = '1234';

  keys.forEach(key => {
    key.addEventListener('click', () => {
      const text = key.textContent.trim();

      if (text === 'AC') {
        currentVal = '0';
      } else if (text === '=') {
        if (currentVal.includes('1234')) {
          display.textContent = '🔓 DESBLOQUEADO';
          display.style.color = '#10B981';
          setTimeout(() => {
            currentVal = '0';
            display.textContent = currentVal;
            display.style.color = '#F8FAFC';
          }, 2000);
          return;
        } else {
          try {
            // Safe evaluation for basic math
            const expr = currentVal.replace(/×/g, '*').replace(/÷/g, '/');
            currentVal = String(Function(`'use strict'; return (${expr})`)() || 0);
          } catch {
            currentVal = 'Error';
          }
        }
      } else if (['+', '-', '×', '÷', '%'].includes(text)) {
        currentVal += text;
      } else if (text === '+/-') {
        if (currentVal.startsWith('-')) {
          currentVal = currentVal.substring(1);
        } else if (currentVal !== '0') {
          currentVal = '-' + currentVal;
        }
      } else {
        if (currentVal === '0' || currentVal === 'Error') {
          currentVal = text;
        } else if (currentVal.length < 12) {
          currentVal += text;
        }
      }

      display.textContent = currentVal;
    });
  });

  // 2. Navbar elevation on scroll
  const navbar = document.getElementById('navbar');
  if (navbar) {
    window.addEventListener('scroll', () => {
      if (window.scrollY > 20) {
        navbar.style.background = 'rgba(11, 15, 23, 0.95)';
        navbar.style.boxShadow = '0 4px 20px rgba(0, 0, 0, 0.3)';
      } else {
        navbar.style.background = 'rgba(11, 15, 23, 0.85)';
        navbar.style.boxShadow = 'none';
      }
    });
  }

  // 3. Sincronización Automática con la última versión de GitHub Releases
  const fetchLatestRelease = async () => {
    try {
      const response = await fetch('https://api.github.com/repos/thelioning/InclusiChat/releases/latest');
      if (!response.ok) return;
      const data = await response.json();
      
      const tagName = data.tag_name || 'v1.0.3';
      const versionClean = tagName.replace(/^v/, '');
      
      // Buscar el asset APK
      const apkAsset = (data.assets || []).find(a => a.name.endsWith('.apk'));
      const apkUrl = apkAsset ? apkAsset.browser_download_url : `https://github.com/thelioning/InclusiChat/releases/download/${tagName}/InclusiChat-${tagName}.apk`;
      const apkName = apkAsset ? apkAsset.name : `InclusiChat-${tagName}.apk`;
      const apkSizeMb = apkAsset ? `${(apkAsset.size / (1024 * 1024)).toFixed(0)} MB` : '59 MB';

      // Actualizar enlace principal del hero
      const heroDownloadBtn = document.getElementById('download-hero-btn');
      if (heroDownloadBtn && apkUrl) {
        heroDownloadBtn.setAttribute('href', '#descarga');
      }

      // Actualizar enlace y texto de la tarjeta de descarga
      const apkLink = document.getElementById('btn-download-apk');
      const apkText = document.getElementById('download-apk-text');
      const versionTag = document.getElementById('download-version-tag');
      const stepFilename = document.getElementById('download-step-filename');

      if (apkLink) apkLink.setAttribute('href', apkUrl);
      if (apkText) apkText.textContent = `${apkName} (${apkSizeMb})`;
      if (versionTag) versionTag.textContent = `${versionClean} (Release Estable)`;
      if (stepFilename) stepFilename.textContent = apkName;
    } catch (_) {
      // Si falla la API de GitHub, se mantienen los valores estáticos por defecto
    }
  };

  fetchLatestRelease();
});
