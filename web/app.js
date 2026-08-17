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
  window.addEventListener('scroll', () => {
    if (window.scrollY > 20) {
      navbar.style.background = 'rgba(11, 15, 23, 0.95)';
      navbar.style.boxShadow = '0 4px 20px rgba(0, 0, 0, 0.3)';
    } else {
      navbar.style.background = 'rgba(11, 15, 23, 0.85)';
      navbar.style.boxShadow = 'none';
    }
  });
});
