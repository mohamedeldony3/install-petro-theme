import fs from "fs";
import path from "path";

export default function handler(req, res) {
  const auth = req.headers.authorization;

  // اسم المستخدم وكلمة المرور (عدّلهم زي ما تحب)
  const username = "elsony";
  const password = "01061";

  // لو مفيش مصادقة، نرجع طلب تسجيل الدخول
  if (!auth) {
    res.setHeader("WWW-Authenticate", 'Basic realm="Restricted Area"');
    return res.status(401).send("Authentication required");
  }

  // تحليل الهيدر
  const [scheme, encoded] = auth.split(" ");
  if (scheme !== "Basic") {
    return res.status(400).send("Invalid authentication scheme");
  }

  const decoded = Buffer.from(encoded, "base64").toString();
  const [user, pass] = decoded.split(":");

  // التحقق من البيانات
  if (user === username && pass === password) {
    try {
      // قراءة الملف bash من نفس المجلد
      const filePath = path.join(process.cwd(), "jishnu-manager.sh");
      const content = fs.readFileSync(filePath, "utf8");

      // إرسال المحتوى
      res.setHeader("Content-Type", "text/plain; charset=utf-8");
      res.status(200).send(content);
    } catch (err) {
      res.status(500).send("Error reading script file: " + err.message);
    }
  } else {
    res.setHeader("WWW-Authenticate", 'Basic realm="Restricted Area"');
    res.status(401).send("Unauthorized");
  }
}