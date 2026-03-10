import asyncio
import logging
import os
from aiogram import Bot, Dispatcher, types, F
from aiogram.filters import Command
from aiogram.fsm.context import FSMContext
from aiogram.fsm.state import State, StatesGroup
from aiogram.types import ReplyKeyboardMarkup, KeyboardButton, ReplyKeyboardRemove

# --- Настройки из переменных окружения (для Railway) ---
# Если запускаете локально без переменных, можно заменить на ваши значения в кавычках
API_TOKEN = os.getenv("BOT_TOKEN", "8770551705:AAE_GYKdrx_r9ODaNNSVq1JskbqUnOyKgp0")
ADMIN_ID = int(os.getenv("ADMIN_ID", "1874217603"))

logging.basicConfig(level=logging.INFO)

bot = Bot(token=API_TOKEN)
dp = Dispatcher()

# --- Состояния (FSM) ---
class Survey(StatesGroup):
    waiting_for_agreement = State()
    waiting_for_name = State()
    waiting_for_phone = State()
    answering_questions = State()

# --- Список вопросов ---
QUESTIONS = [
    "Бывает ли у вас давление выше 140/90?",
    "Бывают ли давящие боли за грудиной?",
    "Чувствуете ли вы нехватку воздуха при ходьбе?",
    "Есть ли у вас отеки ног?",
    "Курите ли вы?",
    "Есть ли у вас лишний вес?",
    "Бывают ли приступы сильного сердцебиения?",
    "Есть ли у близких родственников болезни сердца до 55 лет?",
    "Страдаете ли вы сахарным диабетом?",
    "Мало ли вы двигаетесь в течение дня?",
    "Часто ли вы просыпаетесь ночью от удушья?"
]

# --- Клавиатуры ---
def get_yes_no_kb():
    return ReplyKeyboardMarkup(
        keyboard=[[KeyboardButton(text="Да"), KeyboardButton(text="Нет")]],
        resize_keyboard=True
    )

start_kb = ReplyKeyboardMarkup(
    keyboard=[[KeyboardButton(text="Согласен, начать тест")]],
    resize_keyboard=True
)

phone_kb = ReplyKeyboardMarkup(
    keyboard=[[KeyboardButton(text="Отправить мой номер телефона", request_contact=True)]],
    resize_keyboard=True
)

# --- Обработка команд ---

@dp.message(Command("start"))
async def cmd_start(message: types.Message, state: FSMContext):
    await state.clear()
    welcome_text = (
        "❤️ **Добро пожаловать в систему кардиологического скрининга.**\n\n"
        "⚠️ **ДИСКЛЕЙМЕР:** Данный бот не является врачом и не ставит диагноз. "
        "Результаты носят информационный характер.\n\n"
        "Вы согласны продолжить?"
    )
    await message.answer(welcome_text, reply_markup=start_kb, parse_mode="Markdown")
    await state.set_state(Survey.waiting_for_agreement)

@dp.message(Survey.waiting_for_agreement, F.text == "Согласен, начать тест")
async def process_agreement(message: types.Message, state: FSMContext):
    await message.answer("Пожалуйста, введите ваше **ФИО**:", reply_markup=ReplyKeyboardRemove(), parse_mode="Markdown")
    await state.set_state(Survey.waiting_for_name)

@dp.message(Survey.waiting_for_name)
async def process_name(message: types.Message, state: FSMContext):
    await state.update_data(full_name=message.text)
    await message.answer("Нажмите кнопку ниже, чтобы отправить номер телефона:", reply_markup=phone_kb)
    await state.set_state(Survey.waiting_for_phone)

@dp.message(Survey.waiting_for_phone, F.contact)
async def process_phone(message: types.Message, state: FSMContext):
    await state.update_data(phone=message.contact.phone_number)
    await state.update_data(answers_yes=0, current_question=0)
    
    await message.answer("Начинаем опрос. Используйте кнопки 'Да' или 'Нет'.", reply_markup=get_yes_no_kb())
    await message.answer(f"1. {QUESTIONS[0]}")
    await state.set_state(Survey.answering_questions)

@dp.message(Survey.answering_questions, F.text.in_(["Да", "Нет"]))
async def process_question(message: types.Message, state: FSMContext):
    data = await state.get_data()
    q_index = data.get('current_question', 0)
    yes_count = data.get('answers_yes', 0)

    if message.text == "Да":
        yes_count += 1

    q_index += 1

    if q_index < len(QUESTIONS):
        await state.update_data(answers_yes=yes_count, current_question=q_index)
        await message.answer(f"{q_index + 1}. {QUESTIONS[q_index]}", reply_markup=get_yes_no_kb())
    else:
        # Итоги
        if yes_count <= 3:
            risk = "🟢 Низкий риск"
        elif 4 <= yes_count <= 7:
            risk = "🟡 Средний риск (плановый визит)"
        else:
            risk = "🔴 Высокий риск (СРОЧНО к врачу)"

        # Пользователю
        await message.answer(
            f"Тест завершен!\nРезультат: {yes_count} из {len(QUESTIONS)}\n\n**{risk}**",
            reply_markup=ReplyKeyboardRemove(),
            parse_mode="Markdown"
        )

        # Админу
        admin_card = (
            f"⚡️ **Новый пациент!**\n"
            f"👤 ФИО: {data['full_name']}\n"
            f"📞 Тел: `{data['phone']}`\n"
            f"📊 Результат: {yes_count}/11\n"
            f"📝 Риск: {risk}\n"
            f"🔗 [Профиль пользователя](tg://user?id={message.from_user.id})"
        )
        await bot.send_message(ADMIN_ID, admin_card, parse_mode="Markdown")
        await state.clear()

async def main():
    await dp.start_polling(bot)

if __name__ == "__main__":
    asyncio.run(main())
