const pageStyle = {
  fontFamily: 'sans-serif',
  textAlign: 'center',
  marginTop: '15vh',
};

export default function App() {
  return (
    <div style={pageStyle}>
      <h1>Hello World</h1>
      <p>Served by a React app built with Vite and served by Nginx inside Docker</p>
    </div>
  );
}
