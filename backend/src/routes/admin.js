const express = require("express");

const router = express.Router();

router.post("/login", async (req, res) => {
  try {
    const email = String(req.body.email || "").trim();
    const password = String(req.body.password || "").trim();

    const adminEmail = String(process.env.ADMIN_EMAIL || "").trim();
    const adminPassword = String(process.env.ADMIN_PASSWORD || "").trim();

    if (!email || !password) {
      return res.status(400).json({
        error: "Введи email і пароль"
      });
    }

    if (email !== adminEmail || password !== adminPassword) {
      return res.status(401).json({
        error: "Невірний email або пароль"
      });
    }

    res.json({
      success: true,
      admin: {
        email: adminEmail
      }
    });

  } catch (error) {
    res.status(500).json({
      error: error.message
    });
  }
});

router.get("/check", (req, res) => {
  res.json({
    success: true
  });
});

module.exports = router;