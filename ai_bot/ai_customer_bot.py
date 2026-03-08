import os
import sys
import json
import logging
import telebot
import re
from datetime import datetime
from dotenv import load_dotenv
from groq import Groq

# --- 1. CONFIGURATION & LOGGING ---
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import ai_bot.ai_db_helper as db_helper

load_dotenv(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), '.env'))

# ANSI Color Codes
if os.name == 'nt': 
    os.system('color') # Магия для включения цветов в Windows CMD

class Colors:
    BLUE = '\033[94m'
    CYAN = '\033[96m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'

class ColorFormatter(logging.Formatter):
    def format(self, record):
        color = {
            logging.INFO: Colors.BLUE,
            logging.WARNING: Colors.YELLOW,
            logging.ERROR: Colors.RED,
            logging.CRITICAL: Colors.BOLD + Colors.RED
        }.get(record.levelno, Colors.ENDC)
        
        # Для journalctl не нужно время внутри строки, он добавит его сам
        return f"{color}{record.getMessage()}{Colors.ENDC}"

# Настройка логирования
logger = logging.getLogger("TayhuAI")
logger.setLevel(logging.INFO)

# Консольный хендлер с цветами
console_handler = logging.StreamHandler(sys.stdout)
console_handler.setFormatter(ColorFormatter())
logger.addHandler(console_handler)

# Файловый хендлер (без цветов)
file_handler = logging.FileHandler("tayhu_ai.log", encoding='utf-8')
file_handler.setFormatter(logging.Formatter('%(asctime)s - %(levelname)s - %(message)s'))
logger.addHandler(file_handler)

class TayhuBot:
    def __init__(self):
        self.token = os.getenv('AI_BOT_TOKEN')
        if not self.token:
            raise ValueError("❌ AI_BOT_TOKEN не найден!")
        self.bot = telebot.TeleBot(self.token)
        self.groq_key = os.getenv('GROQ_API_KEY')
        self.groq = Groq(api_key=self.groq_key) if self.groq_key else None
        self.logger = logger
        self.sessions = {}
        self.ADMIN_ID = 5644397480
        self.waiting_for_support = set()

        self.system_prompt = """### 🏛️ TAYHU AI v1.0: ЭКСПЕРТ ПО ИНТЕРЬЕРНОМУ ДЕКОРУ

**IMPORTANT: You MUST respond in JSON format.**

#### 👑 ТВОЯ РОЛЬ И ОБРАЗ:
Ты — Tayhu AI, ведущий эксперт по декоративному пластику и рейкам в компании Tayhu. Твоя речь:
- **Профессионально-эстетичная**: Ты знаешь всё о 3D панелях, рейках, молдингах и плинтусах. Ты помогаешь клиентам создать идеальный интерьер.
- **Вдохновляющая и четкая**: Используй уместные эмодзи (✨, 🏛️, 📏, 🧱, 💎, 🏗️), чтобы сделать ответ живым. Используй *курсив* для вежливых оборотов.
- **Консультативная**: Твоя цель — помочь клиенту выбрать лучшее решение для стен и потолков.

#### 🏢 О МАГАЗИНЕ:
Tayhu — премиальный магазин декоративного пластика, реек и 3D-панелей в Ташкенте. Мы предлагаем современные решения для интерьера. Доставка по всему Узбекистану.
- Сайт: **[tayhu.uz](https://tayhu.uz)**
- Контакт администратора: **[@tayhu_admin](https://t.me/tayhu_admin)**

#### 🧠 АЛГОРИТМ МЫШЛЕНИЯ (СТРОГО):
1. **Анализ запроса**: Если клиент спрашивает о товаре — ты **ОБЯЗАНА** использовать `search`.
2. **Видимость товаров**: Рассказывай о товаре, даже если его сейчас **НЕТ в наличии** (помечен ❌ в инструменте). Просто вежливо предупреди об этом.
3. **Описание товара**: ИСПОЛЬЗУЙ ТОЛЬКО описание из инструмента `info`. Не выдумывай технические параметры.
4. **Проверка заказов**: При ID заказа используй `order` сама, не отправляй к админу.

#### 🔧 ИНСТРУМЕНТЫ:
- `search`, `in_stock`, `info`, `order`, `catalog`.

#### 🎨 ШАБЛОНЫ HTML/MARKDOWN:
- **ЛЮБЫЕ ССЫЛКИ**: Всегда **жирные**. Формат: **[Текст](ссылка)**.
- **ВЫВОД ТОВАРА (СТРОГИЙ ШАБЛОН)**:
  **[Название](https://tayhu.uz/product/ID)**
  💰 **Цена**: `45,000` сум
  📝 **Описание**: (Текст из info)
  ✨ **Наличие**:
  • Цвет/Тип: ✅ (в наличии) или ❌ (нет в наличии)

#### 🚫 СТРОГИЕ ТАБУ:
- Никогда не используй HEX-коды цветов (#000000). Только названия словами.
- Не используй нижнее подчеркивание `_` вне ссылок.
- Не выдумывай то, чего нет в описании админа.
"""

#### 💎 ПРИМЕРЫ ОТВЕТОВ (Few-Shot):

Пример 1: Презентация товара (Шаблонная).
User: "Расскажи про эти рейки" (после info)
JSON: {
  "thoughts": "Презентую рейки по шаблону с эмодзи.",
  "action": { "tool": "none" },
  "response": "С радостью расскажу об этой *стильной* модели! ✨\n\n**[Интерьерная рейка Walnut](https://tayhu.uz/product/r1)**\n💰 **Цена**: `45,000` сум\n📝 **Описание**: Декоративная рейка из качественного пластика с текстурой ореха.\n✨ **Наличие**:\n• Орех / 2.8м: ✅\n• Орех / 3м: ❌ (уже разобрали)\n\nЭти рейки станут идеальным акцентом в вашем интерьере! 🏛️ Хотите оформить заказ?"
}

Пример 2: Товар не в наличии.
User: "Есть 3D панели под мрамор?" (search выдал ❌)
JSON: {
  "thoughts": "Товар найден, но его нет в наличии. Все равно рассказываю о нем.",
  "action": { "tool": "none" },
  "response": "У нас были *потрясающие* 3D панели под мрамор, но сейчас их временно нет в наличии... 😔\n\n**[Панель Marble Luxury](https://tayhu.uz/product/p1)**\n💰 **Цена**: `85,000` сум\n📝 **Описание**: Глянцевая 3D панель с имитацией натурального мрамора.\n✨ **Наличие**:\n• Мрамор / 50x50см: ❌\n\nНо не расстраивайтесь! Мы можем подобрать для вас похожую модель в наличии. Желаете посмотреть? 🧱"
}
"""

        self._register_handlers()

    def _get_session(self, user_id):
        now = datetime.now()
        if user_id in self.sessions:
            last_active = self.sessions[user_id]['last_active']
            if (now - last_active).total_seconds() > 3600:
                self.sessions[user_id]['history'] = []
                self.sessions[user_id]['last_active'] = now
                self.logger.info(f"♻️ Session reset for {user_id}")
        if user_id not in self.sessions:
            self.sessions[user_id] = {'history': [], 'last_active': now}
        self.sessions[user_id]['last_active'] = now
        return self.sessions[user_id]

    def _ai_think(self, messages):
        if not self.groq: return None
        MODELS = [
            "meta-llama/llama-4-scout-17b-16e-instruct",
            "qwen/qwen3-32b",
            "llama-3.3-70b-versatile",
            "openai/gpt-oss-120b"
        ]
        last_error = ""
        wait_time = "несколько секунд"
        for model_name in MODELS:
            try:
                self.logger.info(f"🤖 [REQUEST] Model: {model_name}")
                full_msgs = [{"role": "system", "content": self.system_prompt}] + messages
                completion = self.groq.chat.completions.create(
                    model=model_name,
                    messages=full_msgs,
                    temperature=0.1,
                    response_format={"type": "json_object"}
                )
                res = json.loads(completion.choices[0].message.content)
                self.logger.info(f"🧠 [THOUGHT] {res.get('thoughts')}")
                return res
            except Exception as e:
                err_msg = str(e).lower()
                self.logger.warning(f"⚠️ [FAIL] Model {model_name}: {e}")
                if "429" in err_msg or "rate limit" in err_msg:
                    last_error = "overloaded"
                    match = re.search(r'in (\d+m?\s?\d*s)', err_msg)
                    if match: wait_time = match.group(1)
                    continue 
                continue
        if last_error == "overloaded":
            return {"thoughts": "Overload", "action": {"tool": "none"}, "response": f"✨ Нейронные цепи перегружены. Попробуйте через {wait_time}. 🙏"}
        return None

    def _execute_tool(self, action_data, session):
        tool = action_data.get("tool")
        args = action_data.get("args", {})
        if not tool or tool == "none": return None
        self.logger.info(f"🔧 [TOOL] {Colors.BOLD}{tool}{Colors.ENDC} -> {args}")
        try:
            if tool == "search": return db_helper.search(args.get("query", ""))
            elif tool == "info": return db_helper.info(args.get("id", ""))
            elif tool == "catalog": return db_helper.catalog()
            elif tool == "order": return db_helper.order(args.get("id", ""))
            elif tool == "in_stock": return db_helper.in_stock(args.get("start", 0), args.get("stop", 10))
        except Exception as e: return f"Tool Error: {e}"
        return "Unknown tool"

    def _register_handlers(self):
        @self.bot.message_handler(commands=['start'])
        def start(m):
            user_id = m.from_user.id
            session = self._get_session(user_id)
            session['history'] = []
            self.bot.send_message(m.chat.id, "✨ *Добро пожаловать в Tayhu!*\n\nЯ Tayhu AI, ваш персональный консультант по интерьерному декору. Просто напишите, что вы ищете... 🏚️", parse_mode='Markdown')

        @self.bot.message_handler(commands=['manager'])
        def manager(m):
            self.waiting_for_support.add(m.from_user.id)
            self.bot.send_message(m.chat.id, "👨‍💼 Введите ваше сообщение для менеджера:")

        @self.bot.message_handler(func=lambda m: m.chat.id == self.ADMIN_ID and m.reply_to_message)
        def admin_reply(m):
            try:
                original_user_id = m.reply_to_message.forward_from.id
                self.bot.send_message(original_user_id, f"👨‍💼 *Ответ менеджера:*\n\n{m.text}", parse_mode='Markdown')
                self.bot.reply_to(m, "✅ Сообщение доставлено клиенту.")
            except Exception as e: self.bot.reply_to(m, f"❌ Ошибка отправки: {e}")

        @self.bot.message_handler(content_types=['text', 'photo'])
        def main_loop(m):
            user_id = m.from_user.id
            if user_id in self.waiting_for_support:
                self.bot.forward_message(self.ADMIN_ID, m.chat.id, m.message_id)
                self.waiting_for_support.remove(user_id)
                self.bot.send_message(m.chat.id, "✅ Сообщение передано менеджеру.")
                return

            session = self._get_session(user_id)
            user_text = m.text or "[Фото]"
            self.bot.send_chat_action(m.chat.id, 'typing')
            context_messages = session['history'][-20:]
            context_messages.append({"role": "user", "content": user_text})
            session['history'].append({"role": "user", "content": user_text})

            try:
                MAX_ITERATIONS = 4
                iteration = 0
                final_ai_response = {"response": "✨ *Минуточку, я все проверю...*"}
                while iteration < MAX_ITERATIONS:
                    iteration += 1
                    ai_plan = self._ai_think(context_messages)
                    if not ai_plan: break
                    final_ai_response = ai_plan
                    action = ai_plan.get("action")
                    if not action or not isinstance(action, dict): break
                    tool_name = action.get("tool")
                    if not tool_name or tool_name == "none": break
                    
                    tool_result = self._execute_tool(action, session)
                    self.logger.info(f"👁 [OBSERVATION] {str(tool_result)[:100]}...")
                    assistant_msg = {"role": "assistant", "content": json.dumps(ai_plan, ensure_ascii=False)}
                    observation_msg = {"role": "user", "content": f"SYSTEM_OBSERVATION: {tool_result}"}
                    context_messages.append(assistant_msg)
                    context_messages.append(observation_msg)
                    session['history'].append(assistant_msg)
                    session['history'].append(observation_msg)
                
                final_msg = final_ai_response.get("response", "✨")
                try:
                    self.bot.send_message(m.chat.id, final_msg, parse_mode='Markdown', disable_web_page_preview=True)
                except Exception as parse_error:
                    self.logger.warning(f"⚠️ Markdown Parse Error: {parse_error}. Falling back to plain text.")
                    self.bot.send_message(m.chat.id, final_msg, disable_web_page_preview=True)

                session['history'].append({"role": "assistant", "content": json.dumps(final_ai_response, ensure_ascii=False)})
                session['history'] = session['history'][-20:]
            except Exception as e:
                self.logger.error(f"Error: {e}")
                self.bot.send_message(m.chat.id, "✨ Произошла небольшая техническая заминка.")

    def run(self):
        print("🚀 Tayhu AI v1.0 запущена!", flush=True)
        self.bot.infinity_polling()

if __name__ == "__main__":
    try:
        tayhu_bot = TayhuBot()
        tayhu_bot.run()
    except Exception as e:
        print(f"❌ CRITICAL ERROR: {e}")
