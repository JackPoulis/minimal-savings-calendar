# Savings

A small savings tracker you run on your own PC and open from any device on your home network.

- **Balance graph**: a day-by-day balance from a start date to an end date you choose. Tap any day to add, edit or delete money coming in or going out, each with a title.
- **Goal bar**: how much you have today (green), how much your upcoming entries will add by the end date (gray), and what is still missing (red).
- **Loan estimate**: the monthly payment and total interest for a loan amount, APR and term of any whole number of years (1 or more).
- **Shared data**: everything is saved in a local `data.json`. Other open pages, such as your phone, update within a few seconds.

Built with Vite + React. React is the only runtime dependency, and the graph is plain SVG.

## Run

Requires Node.js 20.19+ or 22.12+.

```bash
npm install
npm start
```

`npm start` builds the app and serves it on port **8420** to your whole network:

- On this PC: http://localhost:8420
- On another device: `http://<your-PC-IP>:8420`, where the IP is printed in the terminal

On Windows, allow Node.js through the firewall on **Private networks** when asked, so other devices can connect.

For development with hot reload:

```bash
npm run dev
```

## Data

Your data lives in `data.json` in the project folder. The app creates it on first save, and it is git-ignored. Back it up or copy it to move your data to another machine.

There is no login. Anyone on your local network can open and edit the app, so don't expose port 8420 to the internet.
