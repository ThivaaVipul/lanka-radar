/// The feed's topics in chip order, with their labels.
const topics = {
  'prices': 'Prices',
  'gazettes': 'Gazettes',
  'exams': 'Exams',
  'jobs': 'Jobs',
  'rates': 'Rates',
};

String topicLabel(String topic) =>
    topics[topic] ?? '${topic[0].toUpperCase()}${topic.substring(1)}';
