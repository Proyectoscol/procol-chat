// Apariencia forzada a claro siempre -- pedido explicito del usuario: "por
// defecto la apariencia sea siempre claro... siempre sea clara la
// apariencia". Ignora deliberadamente la preferencia del sistema operativo
// (isOSOnDarkMode) y cualquier eleccion manual guardada antes en
// localStorage (LOCAL_STORAGE_KEYS.COLOR_SCHEME) -- la firma de la funcion
// se mantiene igual para no romper los call sites existentes
// (App.vue#initializeColorTheme/listenToThemeChanges).
export const setColorTheme = () => {
  document.body.classList.remove('dark');
  document.documentElement.style.setProperty('color-scheme', 'light');
};
