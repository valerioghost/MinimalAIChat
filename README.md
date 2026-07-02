# MinimalAIChat

Un'app di chat AI nativa per iOS 15, pensata per far tornare l'intelligenza artificiale anche sui dispositivi più datati.

## Cosa fa

Questa è un'app basata su iOS 15 (arriveranno altre build per altre versioni di iOS se richieste) che sostituisce le versioni web di molte AI, tipo Gemini o ChatGPT. Il mio intento è far tornare l'AI anche su iOS 15, dove molte app di intelligenza artificiale non sono più compatibili.

Per farla funzionare ti serve una API key di un provider AI qualsiasi (vedi sotto come ottenerla) — inserita quella, l'app è pronta all'uso.

## Requisiti

- iPhone con **iOS 15.0** o superiore
- Una **API key** di un provider AI compatibile (OpenAI, Google Gemini, OpenRouter, ecc. — l'app usa un endpoint compatibile con lo standard "Chat Completions")

## Installazione

L'app **non è disponibile sull'App Store**, quindi va installata tramite sideloading. L'`.ipa` allegato alla [Release](../../releases) non è firmato: è il formato corretto per entrambi i metodi qui sotto, non serve modificarlo.

### Opzione 1 — TrollStore
Se il tuo dispositivo è su **iOS 17.0 o precedente** (TrollStore sfrutta una vulnerabilità corretta da Apple a partire da iOS 17.0.1, quindi non funziona su versioni più recenti):
1. Installa [TrollStore](https://github.com/opa334/TrollStore) sul dispositivo
2. Apri TrollStore e installa `Payload.ipa` scaricato dalla Release
3. L'app resta installata in modo permanente, senza bisogno di ri-firma

### Opzione 2 — AltStore / Sideloadly
Funziona su **qualsiasi versione di iOS attuale**, perché questi strumenti ri-firmano l'app con il tuo Apple ID durante l'installazione:
1. Installa [AltStore](https://altstore.io) o [Sideloadly](https://sideloadly.io) sul computer
2. Collega l'iPhone e segui la procedura guidata per installare `Payload.ipa`
3. Con un Apple ID gratuito l'app va ri-firmata ogni 7 giorni; con un account Apple Developer a pagamento dura 1 anno

## Come ottenere una API key

L'app supporta qualsiasi provider con un endpoint compatibile "Chat Completions". Ecco dove trovarne una:

### Google Gemini
1. Vai su [aistudio.google.com/app/apikey](https://aistudio.google.com/app/apikey)
2. Accedi con un account Google e accetta i termini
3. Clicca su **Create API key**
4. Ha un piano gratuito con limiti di richieste giornaliere

### OpenAI (GPT)
1. Vai su [platform.openai.com/api-keys](https://platform.openai.com/api-keys)
2. Accedi o crea un account (nota: è diverso dall'abbonamento ChatGPT Plus, che **non** dà accesso alle API)
3. Clicca su **Create new secret key** e copiala subito — non sarà più visibile dopo
4. Serve aggiungere un metodo di pagamento in **Billing** per poterla usare oltre i limiti minimi gratuiti

### OpenRouter
Utile se vuoi accedere a più modelli (OpenAI, Anthropic, Google, Meta, ecc.) con una sola chiave:
1. Vai su [openrouter.ai/keys](https://openrouter.ai/keys)
2. Accedi/registrati e aggiungi credito
3. Clicca su **Create Key**

> ⚠️ Non condividere mai la tua API key pubblicamente e non committarla nel codice. L'app la salva localmente nel Keychain del dispositivo, non in chiaro.

## Note tecniche

- Scritta in SwiftUI
- Target minimo: iOS 15.0
- La API key viene salvata in modo sicuro tramite Keychain e usata solo per le chiamate dirette al provider scelto

## Contributi

Segnalazioni e pull request sono benvenute.
