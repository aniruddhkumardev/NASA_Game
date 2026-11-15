import React from "react";
import { createRoot } from "react-dom/client";
import LunarOperationsHUD from "./components/LunarOperationsHUD.jsx";
import "./hud-demo.css";

createRoot(document.getElementById("root")).render(
  <React.StrictMode>
    <main className="demo-page">
      <LunarOperationsHUD initialDay={47} initialPhase={3} />
    </main>
  </React.StrictMode>,
);
