# Known Issues & Limitations / Problemi Noti e Limitazioni
**Version: 0.1a (Prototype)**

This document lists the current limitations of AINABOX. We are open to contributions and suggestions to resolve these points.
*Questo documento elenca le limitazioni attuali di AINABOX. Siamo aperti a contributi e suggerimenti per risolvere questi punti.*

---

## 🇬🇧 English

### 1. Text-to-Speech (TTS) Language
Currently, the TTS system is not fully optimized for English. Voice quality and availability may vary or be limited to specific languages.

### 2. Stability & Updates
AINABOX is a complex orchestration of multiple third-party services. Updating individual components (like Ollama or Open WebUI) independently may lead to configuration mismatches and could potentially break the system. We recommend using the official AINABOX updates.

### 3. ComfyUI "Not Secure" Warning
When accessing ComfyUI, your browser may display a warning stating that the site is "Not Secure".
**Why this happens:** ComfyUI runs on a local HTTP server without an SSL certificate. Since the traffic remains entirely within your local machine/network and does not travel over the internet, this is safe. You can proceed by clicking "Advanced" -> "Proceed to [address] (unsafe)".

### 4. Testing Scope & Hardware Validation
AINABOX has been validated on Linux Mint using hardware from 2013 and 2022. While it is theoretically compatible with most Linux distributions and NVIDIA GPUs, a comprehensive cross-architecture testing phase is still pending. We encourage users of different distros to report their experience.

### 5. GPU Support (NVIDIA vs AMD)
Full GPU acceleration is currently supported for NVIDIA hardware. Support for AMD GPUs is under development. We are actively seeking feedback and contributions from users with AMD hardware to accelerate this implementation.

---

## 🇮🇹 Italiano

### 1. Lingua del Text-to-Speech (TTS)
Al momento, il sistema TTS non è completamente ottimizzato per la lingua inglese. La qualità della voce e la disponibilità potrebbero variare o essere limitate a lingue specifiche.

### 2. Stabilità e Aggiornamenti
AINABOX è un'orchestrazione complessa di molteplici servizi di terze parti. L'aggiornamento indipendente dei singoli componenti (come Ollama o Open WebUI) potrebbe causare incongruenze nelle configurazioni e potenzialmente rompere il sistema. Si raccomanda di utilizzare gli aggiornamenti ufficiali di AINABOX.

### 3. Avviso "Sito non sicuro" in ComfyUI
Durante l'accesso a ComfyUI, il browser potrebbe mostrare un avviso indicando che il sito "non è sicuro".
**Perché succede:** ComfyUI gira su un server HTTP locale senza un certificato SSL. Poiché il traffico rimane interamente all'interno della tua macchina/rete locale e non viaggia su internet, l'operazione è sicura. È possibile procedere cliccando su "Avanzate" -> "Procedi verso [indirizzo] (non sicuro)".

### 4. Ambito di Testing e Validazione Hardware
AINABOX è stato validato su Linux Mint utilizzando hardware del 2013 e del 2022. Sebbene sia teoricamente compatibile con la maggior parte delle distribuzioni Linux e le GPU NVIDIA, manca ancora una fase di testing completa su diverse architetture. Invitiamo gli utenti di altre distribuzioni a segnalare la propria esperienza.

### 5. Supporto GPU (NVIDIA vs AMD)
L'accelerazione GPU è attualmente supportata per l'hardware NVIDIA. Il supporto per le GPU AMD è in fase di sviluppo. Siamo alla ricerca di feedback e contributi da parte di utenti con hardware AMD per accelerare questa implementazione.

---

**Contributions are welcome!** If you have a fix for any of these issues, please open an Issue or a Pull Request.
*I contributi sono benvenuti! Se hai una soluzione per uno di questi problemi, apri pure una Issue o una Pull Request.*
