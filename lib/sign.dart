// IMPORT DES LIBRAIRIES FLUTTER
// MaterialApp et tous les widgets de base de Flutter
import 'package:flutter/material.dart';

// CLASSE PRINCIPALE - C'est le widget sans état (StatefulWidget signifie que le widget peut changer)
// StatefulWidget = un widget qui peut avoir des changements d'état (état = données qui changent)
class ConnexionScreen extends StatefulWidget {
  // Le constructeur : c'est la méthode qui crée une instance de ConnexionScreen
  const ConnexionScreen({Key? key}) : super(key: key);

  // Cette méthode crée l'état mutable (la partie qui peut changer)
  // Elle retourne une instance de _ConnexionScreenState
  @override
  State<ConnexionScreen> createState() => _ConnexionScreenState();
}

// CLASSE D'ETAT - C'est ici que se trouve la logique qui change
// Le underscore (_) signifie que cette classe est "private" (privée, utilisée seulement dans ce fichier)
class _ConnexionScreenState extends State<ConnexionScreen> {
  
  // ========== VARIABLES D'ETAT ==========
  
  // Contrôleur pour le champ email/téléphone
  // Il permet de récupérer le texte entré par l'utilisateur et de le gérer
  final TextEditingController emailController = TextEditingController();
  
  // Contrôleur pour le champ mot de passe
  final TextEditingController passwordController = TextEditingController();
  
  // Variable booléenne (vrai ou faux) pour masquer/afficher le mot de passe
  // true = mot de passe caché, false = mot de passe visible
  bool obscurePassword = true;

  // ========== MÉTHODE DISPOSE ==========
  
  // Cette méthode est appelée quand le widget est supprimé/fermé
  // Elle permet de "nettoyer" et libérer la mémoire
  // IMPORTANT : toujours supprimer les contrôleurs pour éviter les fuites mémoire
  @override
  void dispose() {
    emailController.dispose(); // Détruit le contrôleur email
    passwordController.dispose(); // Détruit le contrôleur mot de passe
    super.dispose(); // Appelle la méthode dispose du parent
  }

  // ========== MÉTHODE BUILD ==========
  
  // C'est la méthode principale qui "construit" (crée) l'interface
  // Elle retourne un Widget qui est affiché à l'écran
  @override
  Widget build(BuildContext context) {
    // Scaffold = la structure de base d'une page (app bar, body, etc.)
    return Scaffold(
      // body = le corps principal de la page
      body: Container(
        // Container = une boîte qui peut contenir d'autres widgets
        // Ici on crée un arrière-plan avec un dégradé de couleurs
        
        // decoration = les propriétés visuelles (couleurs, ombres, etc.)
        decoration: BoxDecoration(
          // gradient = un dégradé de couleurs qui change progressivement
          gradient: LinearGradient(
            // begin = point de départ du dégradé (haut-gauche)
            begin: Alignment.topLeft,
            // end = point de fin du dégradé (bas-droite)
            end: Alignment.bottomRight,
            // colors = liste des couleurs du dégradé
            // #FCF9ED = couleur claire (beige clair)
            // #FFE5B4 = couleur plus foncée (beige doré)
            colors: [
              Color(0xFFFCF9ED), // Couleur 1
              Color(0xFFFFE5B4), // Couleur 2
            ],
          ),
        ),
        
        // Stack = empile les widgets les uns sur les autres
        // (comme des calques dans Photoshop)
        child: Stack(
          children: [
            
            // ========== CHIFFRES EN ARRIÈRE-PLAN ==========
            // Positioned = positionne un widget à un endroit exact
            
            // CHIFFRE "7" - en haut à gauche
            Positioned(
              top: 50, // 50 pixels du haut
              left: 30, // 30 pixels de la gauche
              child: Text(
                '7', // Le texte à afficher
                style: TextStyle(
                  fontSize: 180, // Taille très grande
                  fontWeight: FontWeight.bold, // Texte gras
                  // Color() = couleur, withOpacity() = transparence
                  // 0.1 = très transparent (10% opaque)
                  color: Colors.black.withOpacity(0.1),
                  height: 1, // Hauteur de ligne
                ),
              ),
            ),
            
            // CHIFFRE "8" - en bas à gauche
            Positioned(
              bottom: 100, // 100 pixels du bas
              left: 80, // 80 pixels de la gauche
              child: Text(
                '8',
                style: TextStyle(
                  fontSize: 200,
                  fontWeight: FontWeight.bold,
                  color: Colors.black.withOpacity(0.1),
                  height: 1,
                ),
              ),
            ),
            
            // CHIFFRE "9" - en bas à gauche (position 2)
            Positioned(
              bottom: 50, // 50 pixels du bas
              left: 200, // 200 pixels de la gauche
              child: Text(
                '9',
                style: TextStyle(
                  fontSize: 160,
                  fontWeight: FontWeight.bold,
                  color: Colors.black.withOpacity(0.1),
                  height: 1,
                ),
              ),
            ),
            
            // CHIFFRE "2" - en haut à droite
            Positioned(
              top: 150, // 150 pixels du haut
              right: 50, // 50 pixels de la droite
              child: Text(
                '2',
                style: TextStyle(
                  fontSize: 140,
                  fontWeight: FontWeight.bold,
                  color: Colors.black.withOpacity(0.08), // Encore plus transparent
                  height: 1,
                ),
              ),
            ),
            
            // CHIFFRE "5" - à droite au milieu
            Positioned(
              top: 300, // 300 pixels du haut
              right: 100, // 100 pixels de la droite
              child: Text(
                '5',
                style: TextStyle(
                  fontSize: 150,
                  fontWeight: FontWeight.bold,
                  color: Colors.black.withOpacity(0.1),
                  height: 1,
                ),
              ),
            ),
            
            // CHIFFRE "4" - en bas à droite
            Positioned(
              bottom: 200, // 200 pixels du bas
              right: 40, // 40 pixels de la droite
              child: Text(
                '4',
                style: TextStyle(
                  fontSize: 180,
                  fontWeight: FontWeight.bold,
                  color: Colors.black.withOpacity(0.08),
                  height: 1,
                ),
              ),
            ),
            
            // ========== CONTENU PRINCIPAL (LE FORMULAIRE) ==========
            
            // Center = centre le widget au milieu de l'écran
            Center(
              // SingleChildScrollView = permet de scroller si le contenu est trop grand
              // (utile sur les petits écrans)
              child: SingleChildScrollView(
                // Padding = ajoute un espace/marge autour du contenu
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0), // 24 pixels à gauche et droite
                  // Container = une boîte pour regrouper les éléments
                  child: Container(
                    // padding = espace intérieur de la boîte
                    padding: const EdgeInsets.all(32.0), // 32 pixels partout à l'intérieur
                    // decoration = style visuel de la boîte
                    decoration: BoxDecoration(
                      // color = couleur de fond
                      // #D3EFF6 = bleu clair (couleur du formulaire)
                      color: Color(0xFFD3EFF6),
                      // borderRadius = angles arrondis
                      borderRadius: BorderRadius.circular(24.0), // 24 pixels de rayon
                      // boxShadow = ombre sous la boîte
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1), // Ombre noire très légère
                          blurRadius: 20, // 20 pixels de flou
                          offset: Offset(0, 10), // Décalage de 10 pixels vers le bas
                        ),
                      ],
                    ),
                    // Column = arrange les enfants verticalement (de haut en bas)
                    child: Column(
                      // mainAxisSize = la colonne prend seulement l'espace nécessaire
                      mainAxisSize: MainAxisSize.min,
                      // crossAxisAlignment = alignement horizontal
                      // center = centré horizontalement
                      crossAxisAlignment: CrossAxisAlignment.center,
                      // children = la liste des widgets dans la colonne
                      children: [
                        
                        // ========== TITRE ==========
                        Text(
                          'Connexion', // Le texte
                          style: TextStyle(
                            fontSize: 32, // Taille grande
                            fontWeight: FontWeight.bold, // Gras
                            color: Colors.black87, // Noir presque pur
                          ),
                        ),
                        // SizedBox = crée un espace vide de hauteur fixe
                        SizedBox(height: 32), // 32 pixels d'espace
                        
                        // ========== CHAMP EMAIL/TÉLÉPHONE ==========
                        
                        // Align = aligne le widget dans une direction
                        Align(
                          alignment: Alignment.centerLeft, // Aligné à gauche
                          // Text = simple texte
                          child: Text(
                            'Adresse email ou numéro de téléphone',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600, // Semi-gras
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        SizedBox(height: 10), // Petit espace entre le label et le champ
                        
                        // TextField = champ de texte que l'utilisateur peut remplir
                        TextField(
                          controller: emailController, // Lié au contrôleur email
                          // decoration = comment le champ ressemble
                          decoration: InputDecoration(
                            hintText: 'Entrez votre email ou téléphone', // Texte gris qui disparaît au clic
                            hintStyle: TextStyle(
                              color: Colors.black38, // Gris clair
                            ),
                            filled: true, // Le champ a une couleur de fond
                            fillColor: Colors.white, // Fond blanc
                            // border = la bordure du champ
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12), // Coins arrondis
                              borderSide: BorderSide.none, // Pas de bordure visible
                            ),
                            // contentPadding = espace intérieur du champ
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 16, // 16 pixels à gauche et droite
                              vertical: 14, // 14 pixels en haut et bas
                            ),
                          ),
                          style: TextStyle(
                            color: Colors.black87, // Couleur du texte que l'utilisateur tape
                            fontSize: 14,
                          ),
                        ),
                        SizedBox(height: 24), // Espace avant le champ suivant
                        
                        // ========== CHAMP MOT DE PASSE ==========
                        
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Mot de passe',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        SizedBox(height: 10),
                        
                        TextField(
                          controller: passwordController, // Lié au contrôleur mot de passe
                          // obscureText = masque les caractères (les remplace par des points)
                          obscureText: obscurePassword, // Dépend de la variable obscurePassword
                          decoration: InputDecoration(
                            hintText: 'Entrez votre mot de passe',
                            hintStyle: TextStyle(
                              color: Colors.black38,
                            ),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            // suffixIcon = icône à la fin du champ (pour montrer/cacher le mot de passe)
                            suffixIcon: IconButton(
                              // icon = l'icône affichée
                              // ternaire (condition ? vrai : faux) = si obscurePassword est vrai, montre visibility_off, sinon visibility
                              icon: Icon(
                                obscurePassword
                                    ? Icons.visibility_off // Oeil barré (caché)
                                    : Icons.visibility, // Oeil normal (visible)
                                color: Colors.black54,
                              ),
                              // onPressed = ce qui se passe au clic
                              onPressed: () {
                                // setState = dit à Flutter que quelque chose a changé
                                setState(() {
                                  // Inverse la valeur de obscurePassword
                                  // si true devient false, si false devient true
                                  obscurePassword = !obscurePassword;
                                });
                              },
                            ),
                          ),
                          style: TextStyle(
                            color: Colors.black87,
                            fontSize: 14,
                          ),
                        ),
                        SizedBox(height: 16),
                        
                        // ========== LIEN MOT DE PASSE OUBLIÉ ==========
                        
                        Align(
                          alignment: Alignment.centerRight, // Aligné à droite
                          // GestureDetector = détecte les gestes/clics de l'utilisateur
                          child: GestureDetector(
                            // onTap = ce qui se passe au clic
                            onTap: () {
                              // ScaffoldMessenger = affiche une notification en bas de l'écran
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Réinitialisation du mot de passe',
                                  ),
                                ),
                              );
                            },
                            // Le texte du lien
                            child: Text(
                              'Mot de passe oublié ?',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF0099FF), // Bleu pour ressembler à un lien
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: 32),
                        
                        // ========== BOUTON VALIDER ==========
                        
                        // SizedBox = boîte de taille fixe
                        // Ici on l'utilise pour faire un bouton en largeur complète
                        SizedBox(
                          width: double.infinity, // Largeur maximale possible
                          // ElevatedButton = bouton surélevé (avec ombre)
                          child: ElevatedButton(
                            // onPressed = ce qui se passe au clic du bouton
                            onPressed: () {
                              // Affiche un message quand on clique
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    // emailController.text = récupère le texte dans le champ email
                                    'Connexion avec: ${emailController.text}',
                                  ),
                                ),
                              );
                            },
                            // style = comment le bouton ressemble
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Color(0xFF00B8E6), // Bleu cyan
                              // padding = espace intérieur du bouton
                              padding: EdgeInsets.symmetric(vertical: 16), // 16 pixels en haut et bas
                              // shape = forme du bouton
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12), // Coins arrondis
                              ),
                              elevation: 8, // Hauteur de l'ombre (8 pixels)
                            ),
                            // child = le contenu du bouton
                            child: Text(
                              'Valider',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white, // Texte blanc
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
