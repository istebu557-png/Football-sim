
import React, { useState } from 'react';
import './App.css';
import SelectionScreen from './components/SelectionScreen';
import MatchScreen from './components/MatchScreen';

function App() {
  const [view, setView] = useState('selection');
  const [matchTeams, setMatchTeams] = useState(null);

  const handleStartMatch = (home, away) => {
    setMatchTeams({ home, away });
    setView('match');
  };

  const handleEndMatch = () => {
    setView('selection');
    setMatchTeams(null);
  };

  return (
    <div className="App">
      {view === 'selection' && (
        <SelectionScreen onStart={handleStartMatch} />
      )}
      {view === 'match' && matchTeams && (
        <MatchScreen
          homeTeam={matchTeams.home}
          awayTeam={matchTeams.away}
          onEnd={handleEndMatch}
        />
      )}
    </div>
  );
}

export default App;
