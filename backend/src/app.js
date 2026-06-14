const express = require("express");
const cors = require("cors");
const helmet = require("helmet");
const morgan = require("morgan");
const path = require("path");

const testRoutes = require("./routes/test");
const pagesRoutes = require("./routes/pages");
const teamRoutes = require("./routes/team");
const projectsRoutes = require("./routes/projects");
const partnersRoutes = require("./routes/partners");
const libraryRoutes = require("./routes/library");
const spacesRoutes = require("./routes/spaces");
const newsRoutes = require("./routes/news");
const formsRoutes = require("./routes/forms");
const adminRoutes = require("./routes/admin");
const contactsRoutes = require("./routes/contacts");
const homeRoutes = require("./routes/home");
const aboutRoutes = require("./routes/about");
const opportunitiesRoutes = require("./routes/opportunities");
const directionsRoutes = require("./routes/directions");

const app = express();

app.use(helmet({
  crossOriginResourcePolicy: false,
  contentSecurityPolicy: false
}));
app.use(cors());
app.use(morgan("dev"));
app.use(express.json());

app.use("/uploads", express.static(path.join(__dirname, "../uploads")));

const frontendPath = path.join(__dirname, "../../");

app.use(express.static(frontendPath));

app.get("/", (req, res) => {
  res.sendFile(path.join(frontendPath, "index.html"));
});

app.get("/api/health", (req, res) => {
  res.json({ ok: true });
});

app.use("/api", testRoutes);
app.use("/api/pages", pagesRoutes);
app.use("/api/team", teamRoutes);
app.use("/api/projects", projectsRoutes);
app.use("/api/partners", partnersRoutes);
app.use("/api/library", libraryRoutes);
app.use("/api/spaces", spacesRoutes);
app.use("/api/news", newsRoutes);
app.use("/api/forms", formsRoutes);
app.use("/api/admin", adminRoutes);
app.use("/api/contacts", contactsRoutes);
app.use("/api/home", homeRoutes);
app.use("/api/about", aboutRoutes);
app.use("/api/opportunities", opportunitiesRoutes);
app.use("/api/directions", directionsRoutes);

app.use((req, res) => {
  res.status(404).json({ error: "Route not found" });
});

module.exports = app;
