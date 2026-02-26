import os
import subprocess
import sys
import time
from rich.console import Console
from rich.panel import Panel
from rich.table import Table
from dotenv import load_dotenv

# Load environment variables
load_dotenv()
from rich.progress import Progress, SpinnerColumn, TextColumn

console = Console()

def clear_screen():
    os.system('cls' if os.name == 'nt' else 'clear')

def run_command(command, description):
    with console.status(f"[bold yellow]{description}...", spinner="dots"):
        try:
            # Use the venv python if available
            python_path = "venv/bin/python3" if os.path.exists("venv/bin/python3") else sys.executable
            
            if "uvicorn" in command:
                process = subprocess.Popen(command, shell=True)
                console.print(f"\n[bold green]✅ {description} completado exitosamente.")
                return process
            
            result = subprocess.run(command, shell=True, capture_output=True, text=True)
            if result.returncode == 0:
                console.print(f"[bold green]✅ {description} completado exitosamente.")
                return True
            else:
                console.print(f"[bold red]❌ Error en {description}:")
                console.print(result.stdout)
                console.print(result.stderr)
                return False
        except Exception as e:
            console.print(f"[bold red]❌ Excepción: {str(e)}")
            return False

def show_header():
    clear_screen()
    console.print(Panel.fit(
        "[bold cyan]HYBRID EA - AI MANAGEMENT SYSTEM[/bold cyan]\n"
        "[dim]Professional MT5 Algorithmic Trading - MacOS Native[/dim]",
        border_style="bright_blue"
    ))

def install_dependencies():
    show_header()
    console.print("[yellow]Instalando dependencias de Python...[/yellow]")
    if not os.path.exists("venv"):
        run_command("python3 -m venv venv", "Creando entorno virtual (venv)")
    
    run_command("venv/bin/pip install --upgrade pip", "Actualizando Pip")
    run_command("venv/bin/pip install -r requirements.txt", "Instalando paquetes desde requirements.txt")
    input("\nPresiona Enter para volver al menú...")

def train_ai():
    show_header()
    console.print("[yellow]Iniciando proceso de entrenamiento...[/yellow]")
    console.print("[dim]Asegúrate de tener history_m15.csv y history_m5.csv en la carpeta.[/dim]\n")
    
    if os.path.exists("history_m15.csv") and os.path.exists("history_m5.csv"):
        run_command("venv/bin/python3 train.py", "Entrenando modelos XGBoost")
    else:
        console.print("[bold red]⚠️ Error: No se encontraron los archivos CSV.[/bold red]")
        console.print("Por favor, exporta el historial de MT5 como indica el README.")
    
    input("\nPresiona Enter para volver al menú...")

def start_server():
    show_header()
    host = os.getenv("SERVER_HOST", "0.0.0.0")
    port = os.getenv("SERVER_PORT", "5000")
    
    console.print(f"[bold green]🚀 Iniciando Servidor de Predicción Real-Time...[/bold green]")
    console.print(f"[dim]El servidor estará escuchando en http://{host}:{port}[/dim]")
    console.print("[dim]Para detenerlo, presiona Ctrl+C[/dim]\n")
    
    try:
        # We use uvicorn directly from venv
        subprocess.run(f"venv/bin/uvicorn api:app --host {host} --port {port}", shell=True)
    except KeyboardInterrupt:
        console.print("\n[yellow]Servidor detenido por el usuario.[/yellow]")
    
    input("\nPresiona Enter para volver al menú...")

def check_status():
    show_header()
    table = Table(title="Estado del Sistema", border_style="cyan")
    table.add_column("Componente", style="bold")
    table.add_column("Estado")
    table.add_column("Detalles")
    
    # 1. Virtual Env
    venv_ok = os.path.exists("venv")
    table.add_row("Entorno Virtual (venv)", "[green]OK[/green]" if venv_ok else "[red]Missing[/red]", "Necesario para ejecutar")
    
    # 2. Models
    swing_ok = os.path.exists("models/swing_model.pkl")
    scalp_ok = os.path.exists("models/scalping_model.pkl")
    
    table.add_row("Modelo Swing", "[green]Listo[/green]" if swing_ok else "[yellow]Pendiente[/yellow]", "models/swing_model.pkl")
    table.add_row("Modelo Scalping", "[green]Listo[/green]" if scalp_ok else "[yellow]Pendiente[/yellow]", "models/scalping_model.pkl")
    
    # 3. CSV Data
    m15_ok = os.path.exists("history_m15.csv")
    m5_ok = os.path.exists("history_m5.csv")
    table.add_row("Datos Históricos", "[green]OK[/green]" if (m15_ok and m5_ok) else "[red]Faltan CSV[/red]", "m15.csv y m5.csv")
    
    console.print(table)
    input("\nPresiona Enter para volver al menú...")

def main():
    while True:
        show_header()
        console.print("[bold white]1.[/bold white] 📥 Instalar Requerimientos Setup")
        console.print("[bold white]2.[/bold white] 🧠 Entrenar Inteligencia Artificial (desde CSV)")
        console.print("[bold white]3.[/bold white] 🚀 Arrancar Servidor de Predicción (MT5 Bridge)")
        console.print("[bold white]4.[/bold white] 📋 Ver Estado del Sistema")
        console.print("[bold white]0.[/bold white] 🚪 Salir")
        
        choice = console.input("\n[bold cyan]Selecciona una opción:[/bold cyan] ")
        
        if choice == "1":
            install_dependencies()
        elif choice == "2":
            train_ai()
        elif choice == "3":
            start_server()
        elif choice == "4":
            check_status()
        elif choice == "0":
            console.print("[yellow]Saliendo... ¡Buen trading![/yellow]")
            break
        else:
            console.print("[red]Opción no válida.[/red]")
            time.sleep(1)

if __name__ == "__main__":
    main()
